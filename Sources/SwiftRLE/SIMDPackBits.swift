// SPDX-License-Identifier: MIT
import Foundation

/// Vectorized PackBits row codec and byte-plane scatter/gather kernels.
/// Every encoded packet sequence is bit-for-bit identical to the greedy 2-byte repeat
/// scalar reference encoder (`PackBitsEncoder` / `DICOMRLEFrame`).
internal enum SIMDPackBits {

    /// Encodes `count` contiguous bytes at `src` into `dst` (which must have capacity at least
    /// `count + (count + 2) / 3`), returning the exact encoded byte count.
    @inline(__always)
    internal static func encodeContiguousRow(
        src: UnsafePointer<UInt8>,
        count: Int,
        dst: UnsafeMutablePointer<UInt8>,
        periodicCheck: () throws -> Void
    ) throws -> Int {
        guard count > 0 else { return 0 }
        let rawSrc = UnsafeRawPointer(src)
        var i = 0
        var outPos = 0
        var nextCheck = 16384

        while i < count {
            if i >= nextCheck {
                try periodicCheck()
                nextCheck = i + 16384
            }

            let val = src[i]
            let maxRun = min(128, count - i)
            var runLen = 1

            if maxRun >= 2 && src[i + 1] == val {
                runLen = 2
                let target64 = UInt64(val) &* 0x0101_0101_0101_0101
                var stoppedEarly = false
                while runLen + 8 <= maxRun {
                    let w = UInt64(littleEndian: rawSrc.loadUnaligned(fromByteOffset: i + runLen, as: UInt64.self))
                    let diff = w ^ target64
                    if diff == 0 {
                        runLen += 8
                    } else {
                        runLen += diff.trailingZeroBitCount >> 3
                        stoppedEarly = true
                        break
                    }
                }
                if !stoppedEarly {
                    while runLen < maxRun && src[i + runLen] == val {
                        runLen += 1
                    }
                }
                dst[outPos] = UInt8(bitPattern: Int8(1 - runLen))
                dst[outPos + 1] = val
                outPos += 2
                i += runLen
            } else {
                let litStart = i
                i += 1
                var litLen = 1
                var foundRepeat = false
                // SWAR 8-byte scan for the earliest adjacent equal pair (src[k] == src[k + 1]).
                while litLen + 8 <= 128 && i + 9 <= count {
                    let w0 = UInt64(littleEndian: rawSrc.loadUnaligned(fromByteOffset: i, as: UInt64.self))
                    let w1 = UInt64(littleEndian: rawSrc.loadUnaligned(fromByteOffset: i + 1, as: UInt64.self))
                    let x = w0 ^ w1
                    let zeroByteMask = (x &- 0x0101_0101_0101_0101) & ~x & 0x8080_8080_8080_8080
                    if zeroByteMask == 0 {
                        i += 8
                        litLen += 8
                    } else {
                        let adv = zeroByteMask.trailingZeroBitCount >> 3
                        i += adv
                        litLen += adv
                        foundRepeat = true
                        break
                    }
                }
                if !foundRepeat {
                    while i < count && litLen < 128 {
                        if i + 1 < count && src[i] == src[i + 1] {
                            break
                        }
                        i += 1
                        litLen += 1
                    }
                }
                dst[outPos] = UInt8(litLen - 1)
                dst.advanced(by: outPos + 1).update(from: src.advanced(by: litStart), count: litLen)
                outPos += 1 + litLen
            }
        }
        return outPos
    }

    /// Extracts one row's byte lane (`lane` in `0..<bytesPerSample`, where `lane == 0` is MSB)
    /// into `laneBuffer` while enforcing canonical sample precision.
    @inline(__always)
    internal static func gatherRowLane(
        bytes: UnsafeRawBufferPointer,
        rowOffset: Int,
        width: Int,
        pixelStride: Int,
        storageBits: Int,
        meaningfulBits: Int,
        sampleType: SampleType,
        effectiveOrder: ByteOrder,
        lane: Int,
        laneBuffer: UnsafeMutablePointer<UInt8>
    ) throws {
        guard let rawBase = bytes.baseAddress else {
            throw CodecError(.storageUnavailable, "Inconsistent source borrow.")
        }
        let u8Base = rawBase.assumingMemoryBound(to: UInt8.self)
        let bytesPerSample = storageBits / 8

        // Fast path 1: Contiguous 16-bit greyscale (`pixelStride == 2`) using SIMD16<UInt16>
        if storageBits == 16 && pixelStride == 2 {
            let needSwap = (effectiveOrder == .bigEndian) != (UInt16(littleEndian: 1) != 1)
            let isMSB = (lane == 0)
            let checkPrecision = meaningfulBits < 16
            let mask16 = checkPrecision ? UInt16((UInt32(1) << meaningfulBits) - 1) : 0xFFFF
            let nonMeaningfulMask = SIMD16<UInt16>(repeating: ~mask16)
            let signShift = 16 - meaningfulBits
            let signShiftVec = SIMD16<Int16>(repeating: Int16(signShift))
            var x = 0

            while x + 16 <= width {
                let bytePos = rowOffset + x * 2
                var v = rawBase.loadUnaligned(fromByteOffset: bytePos, as: SIMD16<UInt16>.self)
                if needSwap {
                    v = (v &<< 8) | (v &>> 8)
                }
                if checkPrecision {
                    if sampleType == .unsignedInteger {
                        if (v & nonMeaningfulMask) != .zero {
                            throw CodecError(.invalidArgument, "Noncanonical Image sample exceeds meaningful precision.")
                        }
                    } else {
                        let signedV = SIMD16<Int16>(truncatingIfNeeded: v)
                        let signExtended = (signedV &<< signShiftVec) &>> signShiftVec
                        if signExtended != signedV {
                            throw CodecError(.invalidArgument, "Noncanonical Image sample exceeds meaningful precision.")
                        }
                    }
                }
                let extracted = SIMD16<UInt8>(truncatingIfNeeded: isMSB ? (v &>> 8) : v)
                UnsafeMutableRawPointer(laneBuffer.advanced(by: x)).storeBytes(of: extracted, as: SIMD16<UInt8>.self)
                x += 16
            }

            while x < width {
                let p = rowOffset + x * 2
                let value = try loadUInt16(bytes, at: p, order: effectiveOrder)
                if checkPrecision {
                    let mask = (UInt32(1) << meaningfulBits) - 1
                    var canonical = UInt32(value) & mask
                    if sampleType == .signedInteger, canonical & (UInt32(1) << (meaningfulBits - 1)) != 0 {
                        canonical |= 65535 ^ mask
                    }
                    guard canonical == UInt32(value) else {
                        throw CodecError(.invalidArgument, "Noncanonical Image sample exceeds meaningful precision.")
                    }
                }
                laneBuffer[x] = UInt8(truncatingIfNeeded: isMSB ? (value >> 8) : value)
                x += 1
            }
            return
        }

        // Fast path 2: 8-bit full-precision interleaved RGB (`pixelStride == 3`, `meaningfulBits == 8`)
        if storageBits == 8 && meaningfulBits == 8 && pixelStride == 3 {
            var srcPtr = u8Base.advanced(by: rowOffset)
            var x = 0
            while x + 8 <= width {
                laneBuffer[x]     = srcPtr[0]
                laneBuffer[x + 1] = srcPtr[3]
                laneBuffer[x + 2] = srcPtr[6]
                laneBuffer[x + 3] = srcPtr[9]
                laneBuffer[x + 4] = srcPtr[12]
                laneBuffer[x + 5] = srcPtr[15]
                laneBuffer[x + 6] = srcPtr[18]
                laneBuffer[x + 7] = srcPtr[21]
                srcPtr = srcPtr.advanced(by: 24)
                x += 8
            }
            while x < width {
                laneBuffer[x] = srcPtr[0]
                srcPtr = srcPtr.advanced(by: 3)
                x += 1
            }
            return
        }

        // General strided / arbitrary meaningfulBits path
        let checkPrecision = meaningfulBits < storageBits
        let mask = (UInt32(1) << meaningfulBits) - 1
        let signBit = UInt32(1) << (meaningfulBits - 1)
        let fullMask: UInt32 = storageBits == 8 ? 255 : 65535
        let shiftBits = 8 * (bytesPerSample - 1 - lane)
        var p = rowOffset
        for x in 0..<width {
            let value: UInt16 = storageBits == 8 ? UInt16(u8Base[p]) : try loadUInt16(bytes, at: p, order: effectiveOrder)
            if checkPrecision {
                var canonical = UInt32(value) & mask
                if sampleType == .signedInteger, (canonical & signBit) != 0 {
                    canonical |= fullMask ^ mask
                }
                guard canonical == UInt32(value) else {
                    throw CodecError(.invalidArgument, "Noncanonical Image sample exceeds meaningful precision.")
                }
            }
            laneBuffer[x] = UInt8(truncatingIfNeeded: value >> shiftBits)
            if x + 1 < width { p += pixelStride }
        }
    }

    /// Decodes a single DICOM RLE segment into its disjoint byte lane in `out`.
    internal static func scatterSegment(
        srcBase: UnsafePointer<UInt8>,
        range: Range<Int>,
        out: UnsafeMutableRawBufferPointer,
        width: Int,
        height: Int,
        pixels: Int,
        budget: Int,
        rowOffset0: Int,
        rowBytes: Int,
        pixelStride: Int,
        byteLane: Int,
        periodicCheck: () throws -> Void
    ) throws {
        guard let outRaw = out.baseAddress else {
            throw CodecError(.storageUnavailable, "Short destination borrow.")
        }
        let outBase = outRaw.assumingMemoryBound(to: UInt8.self)

        var cursor = range.lowerBound
        var produced = 0
        var operations = 0
        var y = 0
        var xInRow = 0
        var currentRowOffset = rowOffset0

        try periodicCheck()

        while produced < pixels {
            if (operations & 1023) == 0 && operations > 0 {
                try periodicCheck()
            }
            guard cursor < range.upperBound else {
                throw CodecError(.malformedInput, "Truncated segment.")
            }
            operations += 1
            guard operations <= budget else {
                throw CodecError(.resourceLimitExceeded, "Segment packet budget exceeded.")
            }
            let control = Int(Int8(bitPattern: srcBase[cursor]))
            cursor += 1
            if control == -128 { continue }

            let count = control >= 0 ? control + 1 : 1 - control
            guard count <= width - xInRow, count <= pixels - produced else {
                throw CodecError(.malformedInput, "Packet crosses row or output extent.")
            }
            let payload = control >= 0 ? count : 1
            guard payload <= range.upperBound - cursor else {
                throw CodecError(.malformedInput, "Truncated packet payload.")
            }

            let dstStart = currentRowOffset + xInRow * pixelStride + byteLane
            if pixelStride == 1 {
                let dstPtr = outBase.advanced(by: dstStart)
                if control >= 0 {
                    dstPtr.update(from: srcBase.advanced(by: cursor), count: count)
                } else {
                    dstPtr.update(repeating: srcBase[cursor], count: count)
                }
            } else if pixelStride == 2 {
                var dstPtr = outBase.advanced(by: dstStart)
                if control >= 0 {
                    var srcPtr = srcBase.advanced(by: cursor)
                    var n = count
                    while n >= 8 {
                        dstPtr[0]  = srcPtr[0]
                        dstPtr[2]  = srcPtr[1]
                        dstPtr[4]  = srcPtr[2]
                        dstPtr[6]  = srcPtr[3]
                        dstPtr[8]  = srcPtr[4]
                        dstPtr[10] = srcPtr[5]
                        dstPtr[12] = srcPtr[6]
                        dstPtr[14] = srcPtr[7]
                        dstPtr = dstPtr.advanced(by: 16)
                        srcPtr = srcPtr.advanced(by: 8)
                        n -= 8
                    }
                    while n > 0 {
                        dstPtr[0] = srcPtr[0]
                        dstPtr = dstPtr.advanced(by: 2)
                        srcPtr = srcPtr.advanced(by: 1)
                        n -= 1
                    }
                } else {
                    let v = srcBase[cursor]
                    var n = count
                    while n >= 8 {
                        dstPtr[0]  = v
                        dstPtr[2]  = v
                        dstPtr[4]  = v
                        dstPtr[6]  = v
                        dstPtr[8]  = v
                        dstPtr[10] = v
                        dstPtr[12] = v
                        dstPtr[14] = v
                        dstPtr = dstPtr.advanced(by: 16)
                        n -= 8
                    }
                    while n > 0 {
                        dstPtr[0] = v
                        dstPtr = dstPtr.advanced(by: 2)
                        n -= 1
                    }
                }
            } else if pixelStride == 3 {
                var dstPtr = outBase.advanced(by: dstStart)
                if control >= 0 {
                    var srcPtr = srcBase.advanced(by: cursor)
                    var n = count
                    while n >= 8 {
                        dstPtr[0]  = srcPtr[0]
                        dstPtr[3]  = srcPtr[1]
                        dstPtr[6]  = srcPtr[2]
                        dstPtr[9]  = srcPtr[3]
                        dstPtr[12] = srcPtr[4]
                        dstPtr[15] = srcPtr[5]
                        dstPtr[18] = srcPtr[6]
                        dstPtr[21] = srcPtr[7]
                        dstPtr = dstPtr.advanced(by: 24)
                        srcPtr = srcPtr.advanced(by: 8)
                        n -= 8
                    }
                    while n > 0 {
                        dstPtr[0] = srcPtr[0]
                        dstPtr = dstPtr.advanced(by: 3)
                        srcPtr = srcPtr.advanced(by: 1)
                        n -= 1
                    }
                } else {
                    let v = srcBase[cursor]
                    var n = count
                    while n >= 8 {
                        dstPtr[0]  = v
                        dstPtr[3]  = v
                        dstPtr[6]  = v
                        dstPtr[9]  = v
                        dstPtr[12] = v
                        dstPtr[15] = v
                        dstPtr[18] = v
                        dstPtr[21] = v
                        dstPtr = dstPtr.advanced(by: 24)
                        n -= 8
                    }
                    while n > 0 {
                        dstPtr[0] = v
                        dstPtr = dstPtr.advanced(by: 3)
                        n -= 1
                    }
                }
            } else {
                var dstIdx = dstStart
                if control >= 0 {
                    for n in 0..<count {
                        outBase[dstIdx] = srcBase[cursor + n]
                        if n + 1 < count { dstIdx += pixelStride }
                    }
                } else {
                    let v = srcBase[cursor]
                    for n in 0..<count {
                        outBase[dstIdx] = v
                        if n + 1 < count { dstIdx += pixelStride }
                    }
                }
            }

            cursor += payload
            produced += count
            xInRow += count
            if xInRow == width {
                xInRow = 0
                y += 1
                if y < height {
                    currentRowOffset += rowBytes
                }
            }
        }

        // At most 64 trailing NOPs, followed by 0 or 1 zero pad byte for even segment length.
        var nops = 0
        while cursor < range.upperBound, srcBase[cursor] == 128 {
            cursor += 1
            nops += 1
            operations += 1
            guard nops <= 64, operations <= budget else {
                throw CodecError(.resourceLimitExceeded, "Trailing NOP budget exceeded.")
            }
            try periodicCheck()
        }
        let padding = (cursor - range.lowerBound) % 2
        guard range.upperBound - cursor == padding,
              padding == 0 || srcBase[cursor] == 0 else {
            throw CodecError(.malformedInput, "Unexplained trailing segment bytes or nonzero padding.")
        }
    }

    /// Normalizes `< storageBits` meaningful bits across a row range `[yStart, yEnd)` of one component,
    /// returning `true` if any sample required masking or sign-extension.
    internal static func normalizeComponentRows(
        out: UnsafeMutableRawBufferPointer,
        componentOffset: Int,
        rowBytes: Int,
        pixelStride: Int,
        width: Int,
        yStart: Int,
        yEnd: Int,
        storageBits: Int,
        meaningfulBits: Int,
        sampleType: SampleType,
        order: ByteOrder
    ) throws -> Bool {
        guard let rawBase = out.baseAddress else { return false }
        var anyNormalized = false

        if storageBits == 16 && pixelStride == 2 {
            let needSwap = (order == .bigEndian) != (UInt16(littleEndian: 1) != 1)
            let mask16 = UInt16((UInt32(1) << meaningfulBits) - 1)
            let maskVec = SIMD16<UInt16>(repeating: mask16)
            let signShift = Int16(16 - meaningfulBits)
            let signShiftVec = SIMD16<Int16>(repeating: signShift)

            for y in yStart..<yEnd {
                let rowBase = componentOffset + y * rowBytes
                var x = 0
                while x + 16 <= width {
                    let bytePos = rowBase + x * 2
                    var oldVec = rawBase.loadUnaligned(fromByteOffset: bytePos, as: SIMD16<UInt16>.self)
                    if needSwap {
                        oldVec = (oldVec &<< 8) | (oldVec &>> 8)
                    }
                    let newVec: SIMD16<UInt16>
                    if sampleType == .unsignedInteger {
                        newVec = oldVec & maskVec
                    } else {
                        let s = SIMD16<Int16>(truncatingIfNeeded: oldVec & maskVec)
                        newVec = SIMD16<UInt16>(truncatingIfNeeded: (s &<< signShiftVec) &>> signShiftVec)
                    }
                    if newVec != oldVec {
                        anyNormalized = true
                        let storeVec = needSwap ? ((newVec &<< 8) | (newVec &>> 8)) : newVec
                        withUnsafeBytes(of: storeVec) { srcBytes in
                            rawBase.advanced(by: bytePos).copyMemory(from: srcBytes.baseAddress!, byteCount: 32)
                        }
                    }
                    x += 16
                }
                while x < width {
                    let p = rowBase + x * 2
                    let old = UInt32(try loadUInt16(UnsafeRawBufferPointer(out), at: p, order: order))
                    let mask = (UInt32(1) << meaningfulBits) - 1
                    var value = old & mask
                    if sampleType == .signedInteger, value & (UInt32(1) << (meaningfulBits - 1)) != 0 {
                        value |= 65535 ^ mask
                    }
                    if value != old {
                        anyNormalized = true
                        try storeUInt16(UInt16(value), into: out, at: p, order: order)
                    }
                    x += 1
                }
            }
            return anyNormalized
        }

        let bytesPerSample = storageBits / 8
        let mask = (UInt32(1) << meaningfulBits) - 1
        let signBit = UInt32(1) << (meaningfulBits - 1)
        let fullMask: UInt32 = bytesPerSample == 1 ? 255 : 65535

        for y in yStart..<yEnd {
            var p = componentOffset + y * rowBytes
            for x in 0..<width {
                let old = bytesPerSample == 1
                    ? UInt32(out[p])
                    : UInt32(try loadUInt16(UnsafeRawBufferPointer(out), at: p, order: order))
                var value = old & mask
                if sampleType == .signedInteger, (value & signBit) != 0 {
                    value |= fullMask ^ mask
                }
                if value != old {
                    anyNormalized = true
                    if bytesPerSample == 1 {
                        out[p] = UInt8(value)
                    } else {
                        try storeUInt16(UInt16(value), into: out, at: p, order: order)
                    }
                }
                if x + 1 < width { p += pixelStride }
            }
        }
        return anyNormalized
    }
}
