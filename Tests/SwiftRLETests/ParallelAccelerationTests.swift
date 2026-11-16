// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import SwiftRLE

@Suite("SIMD & Multi-Worker Parallel Acceleration Tests")
struct ParallelAccelerationTests {

    @Test("Multi-worker SIMD DICOM RLE matches 1T scalar bit-for-bit across clinical & RGB profiles")
    func multiWorkerBitExactEquivalence() throws {
        let encoder = try Encoder()
        let decoder = try Decoder()
        let limits1T = try ResourceLimits(maximumWorkers: 1)
        let limits10T = try ResourceLimits(maximumWorkers: 10)

        // 1. 16-bit unsigned & signed 12-in-16 odd dimensions (333 x 197 = 65,601 pixels -> multi-strip!)
        for signed in [false, true] {
            for bits in [12, 16] {
                for bigEndian in [false, true] {
                    let frame = try RLEFrameDescriptor(
                        width: 333,
                        height: 197,
                        sampleType: signed ? .signedInteger : .unsignedInteger,
                        storageBits: 16,
                        meaningfulBits: bits,
                        byteOrder: bigEndian ? .bigEndian : .littleEndian,
                        rowBytes: 333 * 2 + 6,
                        offset: 2
                    )
                    let mask = (UInt32(1) << bits) - 1
                    let image = try FrameTests.source(frame) { _, x, y in
                        // Mix flat border runs and textured interior
                        if x < 24 || x > 308 || y < 12 {
                            return 0
                        }
                        var v = UInt32((x * 131 + y * 977) & 0xFFFF) & mask
                        if signed && (v & (UInt32(1) << (bits - 1))) != 0 {
                            v |= 0xFFFF ^ mask
                        }
                        return UInt16(v)
                    }

                    let encScalar = try encoder.encodeSynchronously(
                        image,
                        options: EncodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU))
                    )
                    let encAccel1T = try encoder.encodeSynchronously(
                        image,
                        options: EncodeOptions(resourceLimits: limits1T, executionPolicy: .required(.accelerated))
                    )
                    let encAccel10T = try encoder.encodeSynchronously(
                        image,
                        options: EncodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated))
                    )
                    #expect(encScalar.report.backend == .scalarCPU)
                    #expect(encAccel1T.report.backend == .accelerated)
                    #expect(encAccel10T.report.backend == .accelerated)
                    #expect(encAccel1T.data == encScalar.data)
                    #expect(encAccel10T.data == encScalar.data)

                    let codec = try CodecOptions(frameDescriptor: frame)
                    let decScalar = try decoder.decodeSynchronously(
                        encScalar.data,
                        options: DecodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU), codecOptions: codec)
                    )
                    let decAccel10T = try decoder.decodeSynchronously(
                        encAccel10T.data,
                        options: DecodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated), codecOptions: codec)
                    )
                    #expect(decScalar.report.backend == .scalarCPU)
                    #expect(decAccel10T.report.backend == .accelerated)
                    let bytesScalar = try decScalar.image.storage.withUnsafeBytes { Data($0) }
                    let bytesAccel = try decAccel10T.image.storage.withUnsafeBytes { Data($0) }
                    #expect(bytesAccel == bytesScalar)
                }
            }
        }

        // 2. 8-bit & 16-bit RGB interleaved and planar (259 x 131 = 33,929 pixels)
        for storageBits in [8, 16] {
            for planar in [0, 1] {
                let frame = try RLEFrameDescriptor(
                    width: 259,
                    height: 131,
                    storageBits: storageBits,
                    meaningfulBits: storageBits,
                    components: [.red, .green, .blue],
                    colour: .rgb,
                    planarConfiguration: planar
                )
                let maxMask = storageBits == 8 ? 255 : 65535
                let image = try FrameTests.source(frame) { c, x, y in
                    if (x / 19 + y / 13) % 4 == 0 {
                        return UInt16((c * 73 + 42) & maxMask)
                    }
                    return UInt16((c * 211 + x * 37 + y * 53) & maxMask)
                }
                let encScalar = try encoder.encodeSynchronously(
                    image,
                    options: EncodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU))
                )
                let encAccel = try encoder.encodeSynchronously(
                    image,
                    options: EncodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated))
                )
                #expect(encAccel.data == encScalar.data)

                let codec = try CodecOptions(frameDescriptor: frame)
                let decScalar = try decoder.decodeSynchronously(
                    encScalar.data,
                    options: DecodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU), codecOptions: codec)
                )
                let decAccel = try decoder.decodeSynchronously(
                    encAccel.data,
                    options: DecodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated), codecOptions: codec)
                )
                let bytesScalar = try decScalar.image.storage.withUnsafeBytes { Data($0) }
                let bytesAccel = try decAccel.image.storage.withUnsafeBytes { Data($0) }
                #expect(bytesAccel == bytesScalar)
            }
        }
    }

    @Test("SIMD 16-bit gather rejects noncanonical samples identically to scalar")
    func simdNoncanonicalSampleRejection() throws {
        for signed in [false, true] {
            let frame = try RLEFrameDescriptor(
                width: 64,
                height: 4,
                sampleType: signed ? .signedInteger : .unsignedInteger,
                storageBits: 16,
                meaningfulBits: 12
            )
            let badSample: UInt16 = signed ? 0x1800 : 0x1001
            let badImage = try FrameTests.source(frame) { _, x, y in
                (x == 23 && y == 2) ? badSample : 0
            }
            let encoder = try Encoder()
            #expect(throws: CodecError.self) {
                _ = try encoder.encodeSynchronously(badImage, options: EncodeOptions(executionPolicy: .required(.accelerated)))
            }
        }
    }

    @Test("Tight workspace and memory budgets succeed on accelerated path with zero persistent workspace")
    func tightWorkspaceAndMemoryBudgetAccelerated() throws {
        let frame = try RLEFrameDescriptor(
            width: 333,
            height: 197,
            sampleType: .unsignedInteger,
            storageBits: 16,
            meaningfulBits: 12
        )
        let image = try FrameTests.source(frame) { _, x, y in
            UInt16((x * 31 + y * 17) & 0x0FFF)
        }
        let imageBytes = image.storage.byteCount
        let rowCount = 197
        let segments = 2
        let rowBound = 333 + (333 + 2) / 3
        let maxEncodedBound = 64 + segments * (rowCount * rowBound + 1)
        let tightLimits = try ResourceLimits(
            maximumCompressedBytes: maxEncodedBound,
            maximumDecodedBytes: imageBytes,
            maximumWorkspaceBytes: 64,
            maximumPixels: 333 * 197,
            maximumDimension: 333,
            maximumMetadataBytes: 64,
            maximumWorkers: 10,
            maximumMemoryBytes: imageBytes + maxEncodedBound + 64
        )
        let encoder = try Encoder()
        let decoder = try Decoder()
        let encoded = try encoder.encodeSynchronously(
            image,
            options: EncodeOptions(resourceLimits: tightLimits, executionPolicy: .required(.accelerated))
        )
        #expect(encoded.report.backend == .accelerated)
        #expect(encoded.report.peakWorkspaceBytes == 0)

        let codec = try CodecOptions(frameDescriptor: frame)
        let decoded = try decoder.decodeSynchronously(
            encoded.data,
            options: DecodeOptions(resourceLimits: tightLimits, executionPolicy: .required(.accelerated), codecOptions: codec)
        )
        #expect(decoded.report.backend == .accelerated)
        #expect(decoded.report.peakWorkspaceBytes == 0)
        let srcBytes = try image.storage.withUnsafeBytes { Data($0) }
        let dstBytes = try decoded.image.storage.withUnsafeBytes { Data($0) }
        #expect(dstBytes == srcBytes)
    }

    @Test("Async Task cancellation propagates into multi-worker encode and decode")
    func asyncTaskCancellationPropagatesToParallelWorkers() async throws {
        let frame = try RLEFrameDescriptor(
            width: 512,
            height: 512,
            sampleType: .unsignedInteger,
            storageBits: 16,
            meaningfulBits: 16
        )
        let image = try FrameTests.source(frame) { _, x, y in
            UInt16((x * 131 + y * 977) & 0xFFFF)
        }
        let encoder = try Encoder()
        let decoder = try Decoder()
        let baseline = try encoder.encodeSynchronously(image)
        let limits10T = try ResourceLimits(maximumWorkers: 10)
        let codec = try CodecOptions(frameDescriptor: frame)

        let encTask = Task {
            try await encoder.encode(
                image,
                options: EncodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated))
            )
        }
        encTask.cancel()
        do {
            _ = try await encTask.value
        } catch is CancellationError {
            // Expected when cancellation fires before or during parallel encode.
        }

        // Deterministic pre-cancelled Task check inside BoundedParallelPool.withTaskCancellationBridge:
        let preCancelledDecode = Task { () throws -> DecodedImage in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await decoder.decode(
                baseline.data,
                options: DecodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated), codecOptions: codec)
            )
        }
        await #expect(throws: CancellationError.self) {
            _ = try await preCancelledDecode.value
        }
    }

    @Test("Malformed RLE segments are deterministically rejected under multi-worker decode")
    func malformedSegmentsRejectedUnderMultiWorkerDecode() throws {
        let frame = try RLEFrameDescriptor(
            width: 128,
            height: 128,
            sampleType: .unsignedInteger,
            storageBits: 16,
            meaningfulBits: 16
        )
        let codec = try CodecOptions(frameDescriptor: frame)
        let decoder = try Decoder()
        let limits1T = try ResourceLimits(maximumWorkers: 1)
        let limits10T = try ResourceLimits(maximumWorkers: 10)

        func makeHeaderAndSegments(_ seg0: [UInt8], _ seg1: [UInt8]) -> Data {
            var out = Data(count: 64)
            let s0Offset = UInt32(64)
            let s1Offset = UInt32(64 + seg0.count)
            out.replaceSubrange(0..<4, with: withUnsafeBytes(of: UInt32(2).littleEndian) { Data($0) })
            out.replaceSubrange(4..<8, with: withUnsafeBytes(of: s0Offset.littleEndian) { Data($0) })
            out.replaceSubrange(8..<12, with: withUnsafeBytes(of: s1Offset.littleEndian) { Data($0) })
            out.append(contentsOf: seg0)
            out.append(contentsOf: seg1)
            return out
        }

        // Valid segment helper: 128 rows of 128 zeroes -> per row: [0x81 (-127 -> 128 copies), 0x00]
        let validSeg = Array(repeating: [UInt8(0x81), UInt8(0x00)], count: 128).flatMap { $0 }

        // Case 1: Packet crosses row boundary (row 0 emits 64 + 65 = 129 bytes)
        var crossRowSeg: [UInt8] = [UInt8(0xC1), 0x00, UInt8(0xC0), 0x00] // 64 + 65 = 129
        crossRowSeg.append(contentsOf: Array(repeating: [UInt8(0x81), UInt8(0x00)], count: 127).flatMap { $0 })
        if crossRowSeg.count % 2 != 0 { crossRowSeg.append(0x80) }

        // Case 2: Truncated segment (only 127 rows instead of 128)
        let truncatedSeg = Array(repeating: [UInt8(0x81), UInt8(0x00)], count: 127).flatMap { $0 }

        // Case 3: Nonzero trailing padding byte after 128 complete rows
        var nonzeroTailSeg = validSeg
        nonzeroTailSeg.append(contentsOf: [0x80, 0x01]) // 0x80 NOP + 0x01 literal header truncated/nonzero

        for bad in [
            makeHeaderAndSegments(crossRowSeg, validSeg),
            makeHeaderAndSegments(validSeg, truncatedSeg),
            makeHeaderAndSegments(validSeg, nonzeroTailSeg)
        ] {
            #expect(throws: CodecError.self) {
                _ = try decoder.decodeSynchronously(
                    bad,
                    options: DecodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU), codecOptions: codec)
                )
            }
            #expect(throws: CodecError.self) {
                _ = try decoder.decodeSynchronously(
                    bad,
                    options: DecodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated), codecOptions: codec)
                )
            }
        }
    }
}
