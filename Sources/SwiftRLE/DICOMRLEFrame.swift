// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// Structural facts only: geometry and interpretation always remain external.
public struct DICOMRLEHeader: Sendable, Equatable {
    public let segmentRanges: [Range<Int>]
    public init(_ data: Data, expectedSegmentCount: Int? = nil) throws {
        guard data.count >= 64 else { throw CodecError(.malformedInput, "Truncated RLE header.") }
        self.segmentRanges = try data.withUnsafeBytes { bytes in
            func word(_ index: Int) throws -> Int {
                let p = index * 4
                let raw = UInt32(bytes[p]) | UInt32(bytes[p+1]) << 8 | UInt32(bytes[p+2]) << 16 | UInt32(bytes[p+3]) << 24
                guard let value = Int(exactly: raw) else { throw CodecError(.malformedInput, "RLE offset exceeds platform integer range.") }
                return value
            }
            let count = try word(0)
            guard (1...15).contains(count), expectedSegmentCount.map({ $0 == count }) ?? true else {
                throw CodecError(.malformedInput, "RLE segment count disagrees with profile.")
            }
            guard try word(1) == 64 else { throw CodecError(.malformedInput, "First segment must start at 64.") }
            for i in (count+1)..<16 where try word(i) != 0 {
                throw CodecError(.malformedInput, "Unused segment offset is nonzero.")
            }
            return try (0..<count).map { i in
                let start = try word(i+1), end = try i+1 == count ? data.count : word(i+2)
                guard start >= 64, start < end, end <= data.count, (end-start) % 2 == 0 else {
                    throw CodecError(.malformedInput, "Invalid segment extent or alignment.")
                }
                return start..<end
            }
        }
    }
}

/// Full allocated cells, explicitly distinct from canonical meaningful-bit Image.
public struct RawAllocatedCells: Sendable {
    public let descriptor: RLEFrameDescriptor
    public let storage: any ReadOnlyImageStorage
    public let report: OperationReport
}

/// Strict DICOM frame kernel. No decoded plane or pixel repack is allocated.
public enum DICOMRLEFrame {
    static var capabilities: CodecCapabilities {
        CodecCapabilities(
            formats: ["dicom-rle"],
            compressionModes: [.lossless],
            sampleTypes: [.unsignedInteger, .signedInteger],
            meaningfulPrecision: 1...16,
            layouts: [CodecCapabilities.sharedGreyscaleLayout, "8/16-bit-mono-palette", "unsigned-RGB-YBR_FULL-interleaved-planar"],
            availableBackends: AccelerationRuntime.availableBackends,
            canInspect: true,
            canEncode: true,
            canDecode: true
        )
    }

    /// Raw route preserves every allocated bit and supplies no canonical Image.
    public static func decodeAllocatedCells(_ data: Data, descriptor: RLEFrameDescriptor,
                                           options: DecodeOptions = .init()) throws -> RawAllocatedCells {
        let gate = FrameGate(options.resourceLimits)
        if let codec = options.codecOptions {
            guard codec.profile == .dicomRLEFrame,
                  try codec.frameDescriptor.map({ try $0.equivalent(to: descriptor, check: { try gate.check() }) }) ?? true else {
                throw CodecError(.invalidArgument, "Raw allocated-cell options conflict with the external descriptor.")
            }
        }
        let header = try preflight(data, descriptor: descriptor, capacity: descriptor.imageDescriptor.requiredByteCount,
                                   options: options, gate: gate)
        let resolved = try AccelerationRuntime.resolve(options.executionPolicy)
        options.progress?(try ProgressUpdate(phase: .inspecting, completedUnits: 0, totalUnits: 1))
        try gate.check()
        let owner = try OwnedImageStorage(byteCount: descriptor.imageDescriptor.requiredByteCount, limits: options.resourceLimits)
        let lease = try owner.reserveWrite()
        do {
            var normalized = false
            try owner.withUnsafeMutableBytes(lease: lease) { out in
                try scatter(
                    data,
                    header: header,
                    descriptor: descriptor.imageDescriptor,
                    out: out,
                    multiplier: options.codecOptions?.maximumPacketOperationsPerOutputByte ?? 2,
                    canonical: false,
                    normalized: &normalized,
                    gate: gate,
                    policy: options.executionPolicy,
                    backend: resolved.backend,
                    maxWorkers: options.resourceLimits.maximumWorkers
                )
            }
            try gate.check()
            let sealed = try owner.finishAndSeal(lease: lease)
            try gate.check()
            options.progress?(try ProgressUpdate(phase: .completed, completedUnits: 1, totalUnits: 1))
            try gate.check()
            return RawAllocatedCells(
                descriptor: descriptor,
                storage: sealed,
                report: report(
                    backend: resolved.backend,
                    capacity: owner.byteCount,
                    allocations: 1,
                    fallback: resolved.fallbackReason
                )
            )
        } catch {
            try? owner.abortAndInvalidate(lease: lease)
            throw error
        }
    }

    static func report(backend: Backend = .scalarCPU, capacity: Int, allocations: Int, fallback: String?, normalized: Bool = false) -> OperationReport {
        OperationReport(
            backend: backend,
            fallbackReason: fallback,
            fidelity: .exactSamples,
            pixelAllocationCount: allocations,
            peakPixelBytes: capacity,
            peakWorkspaceBytes: 0,
            sampleNormalizations: normalized ? ["Unused allocated bits masked/sign-extended in final output."] : []
        )
    }

    static func preflight(_ data: Data, descriptor: RLEFrameDescriptor, capacity: Int,
                          options: DecodeOptions, gate: FrameGate) throws -> DICOMRLEHeader {
        try gate.check()
        _ = try AccelerationRuntime.resolve(options.executionPolicy)
        try descriptor.imageDescriptor.validate(limits: options.resourceLimits)
        let metadata = try descriptor.metadata.validate(
            limits: options.resourceLimits,
            additionalBytes: descriptor.imageDescriptor.iccProfile?.count ?? 0,
            check: { try gate.check() }
        )
        guard data.count <= options.resourceLimits.maximumCompressedBytes,
              capacity <= options.resourceLimits.maximumDecodedBytes,
              try checkedAdd(checkedAdd(data.count, capacity), metadata) <= options.resourceLimits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Frame exceeds aggregate admission budget.")
        }
        try gate.check()
        let header = try DICOMRLEHeader(data, expectedSegmentCount: descriptor.expectedSegmentCount)
        try gate.check()
        return header
    }

    /// Addressing is resolved only after descriptor validation. It owns no pixels,
    /// scratch planes or pointers.
    private struct ComponentAddressing: Sendable {
        let offset: Int
        let rowBytes: Int
        let pixelStride: Int
        static let reference = Self(offset: 0, rowBytes: 0, pixelStride: 0)
        private init(offset: Int, rowBytes: Int, pixelStride: Int) {
            self.offset = offset; self.rowBytes = rowBytes; self.pixelStride = pixelStride
        }
        init(_ descriptor: ImageDescriptor, component: Int) throws {
            for plane in descriptor.planes {
                if let index = plane.components.firstIndex(of: component) {
                    offset = plane.offset + (index == 0 ? 0 : index * plane.sampleStride)
                    rowBytes = descriptor.height == 1
                        ? 0
                        : (SharedPathMutation.active == .ignoreRowStride ? descriptor.width * plane.pixelStride : plane.rowBytes)
                    pixelStride = descriptor.width == 1 ? 0 : plane.pixelStride
                    return
                }
            }
            throw CodecError(.internalFailure, "Validated component has no plane.")
        }
    }

    private static func usesReferenceAddressing(_ policy: ExecutionPolicy, descriptor: ImageDescriptor) -> Bool {
        if descriptor.width == 1 && descriptor.height == 1 { return true }
        if case .scalarCPU = policy { return true }
        if case .required(.scalarCPU) = policy { return true }
        return false
    }

    static func location(_ descriptor: ImageDescriptor, component: Int, x: Int, y: Int) -> Int {
        for plane in descriptor.planes {
            if let index = plane.components.firstIndex(of: component) {
                let row = SharedPathMutation.active == .ignoreRowStride ? descriptor.width * plane.pixelStride : plane.rowBytes
                return plane.offset
                    + (y == 0 ? 0 : y * row)
                    + (x == 0 ? 0 : x * plane.pixelStride)
                    + (index == 0 ? 0 : index * plane.sampleStride)
            }
        }
        return 0
    }

    static func scatter(
        _ data: Data,
        header: DICOMRLEHeader,
        descriptor: ImageDescriptor,
        out: UnsafeMutableRawBufferPointer,
        multiplier: Int,
        canonical: Bool,
        normalized: inout Bool,
        gate: FrameGate,
        policy: ExecutionPolicy = .automatic,
        backend: Backend = .scalarCPU,
        maxWorkers: Int = 1
    ) throws {
        guard out.count >= descriptor.requiredByteCount else {
            throw CodecError(.storageUnavailable, "Short destination borrow.")
        }
        let bytesPerSample = descriptor.storageBits / 8
        let pixels = try checkedMultiply(descriptor.width, descriptor.height)
        let budget = try checkedAdd(64, checkedMultiply(pixels, multiplier))

        if backend == .accelerated && !(descriptor.width == 1 && descriptor.height == 1) {
            let segmentCount = header.segmentRanges.count
            let order = SharedPathMutation.active == .wrongByteOrder ? descriptor.byteOrder.opposite : descriptor.byteOrder
            var segmentAddressings: [ComponentAddressing] = []
            segmentAddressings.reserveCapacity(segmentCount)
            for segment in 0..<segmentCount {
                let component = segment / bytesPerSample
                segmentAddressings.append(try ComponentAddressing(descriptor, component: component))
            }
            let immutableAddressings = segmentAddressings
            let ranges = header.segmentRanges

            try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                guard let srcRaw = bytes.baseAddress, let outRaw = out.baseAddress else {
                    throw CodecError(.storageUnavailable, "Short destination borrow.")
                }
                let sendableSrc = UnsafeSendableRawPointer(baseAddress: srcRaw, count: bytes.count)
                let sendableOut = UnsafeSendableMutableRawPointer(baseAddress: outRaw, count: out.count)

                try BoundedParallelPool.forEach(jobCount: segmentCount, maxWorkers: maxWorkers) { segment in
                    let lane = segment % bytesPerSample
                    let byteLane = order == .bigEndian ? lane : bytesPerSample - 1 - lane
                    let addressing = immutableAddressings[segment]
                    let outBuf = UnsafeMutableRawBufferPointer(start: sendableOut.baseAddress, count: sendableOut.count)
                    try SIMDPackBits.scatterSegment(
                        srcBase: sendableSrc.baseAddress.assumingMemoryBound(to: UInt8.self),
                        range: ranges[segment],
                        out: outBuf,
                        width: descriptor.width,
                        height: descriptor.height,
                        pixels: pixels,
                        budget: budget,
                        rowOffset0: addressing.offset,
                        rowBytes: addressing.rowBytes,
                        pixelStride: addressing.pixelStride,
                        byteLane: byteLane,
                        periodicCheck: { try gate.check() }
                    )
                }

                if canonical && descriptor.meaningfulBits < descriptor.storageBits {
                    let compCount = descriptor.components.count
                    var compAddressings: [ComponentAddressing] = []
                    compAddressings.reserveCapacity(compCount)
                    for c in 0..<compCount {
                        compAddressings.append(try ComponentAddressing(descriptor, component: c))
                    }
                    let immutableCompAddressings = compAddressings
                    let normFlag = Atomic<Bool>(false)
                    let stripsPerComp = (descriptor.height >= 16 && pixels >= 4096 && maxWorkers > 1)
                        ? min(descriptor.height, max(1, (maxWorkers + compCount - 1) / compCount))
                        : 1
                    let totalJobs = compCount * stripsPerComp
                    let rowsPerStrip = (descriptor.height + stripsPerComp - 1) / stripsPerComp

                    try BoundedParallelPool.forEach(jobCount: totalJobs, maxWorkers: maxWorkers) { job in
                        let comp = job / stripsPerComp
                        let strip = job % stripsPerComp
                        let yStart = strip * rowsPerStrip
                        let yEnd = min(descriptor.height, yStart + rowsPerStrip)
                        guard yStart < yEnd else { return }
                        try gate.check()
                        let outBuf = UnsafeMutableRawBufferPointer(start: sendableOut.baseAddress, count: sendableOut.count)
                        let addr = immutableCompAddressings[comp]
                        let didNormalize = try SIMDPackBits.normalizeComponentRows(
                            out: outBuf,
                            componentOffset: addr.offset,
                            rowBytes: addr.rowBytes,
                            pixelStride: addr.pixelStride,
                            width: descriptor.width,
                            yStart: yStart,
                            yEnd: yEnd,
                            storageBits: descriptor.storageBits,
                            meaningfulBits: descriptor.meaningfulBits,
                            sampleType: descriptor.sampleType,
                            order: descriptor.byteOrder
                        )
                        if didNormalize {
                            normFlag.store(true, ordering: .releasing)
                        }
                    }
                    normalized = normalized || normFlag.load(ordering: .acquiring)
                }
            }
            return
        }

        // Scalar reference path (`backend == .scalarCPU` or 1x1 singleton)
        try data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
            for (segment, range) in header.segmentRanges.enumerated() {
                let component = segment / bytesPerSample, lane = segment % bytesPerSample
                let order = SharedPathMutation.active == .wrongByteOrder ? descriptor.byteOrder.opposite : descriptor.byteOrder
                let byteLane = order == .bigEndian ? lane : bytesPerSample - 1 - lane
                let reference = usesReferenceAddressing(policy, descriptor: descriptor)
                let addressing = try reference ? ComponentAddressing.reference : ComponentAddressing(descriptor, component: component)
                var cursor = range.lowerBound, produced = 0, operations = 0
                while produced < pixels {
                    try gate.check()
                    guard cursor < range.upperBound else { throw CodecError(.malformedInput, "Truncated segment.") }
                    operations += 1
                    guard operations <= budget else { throw CodecError(.resourceLimitExceeded, "Segment packet budget exceeded.") }
                    let control = Int(Int8(bitPattern: bytes[cursor])); cursor += 1
                    if control == -128 { continue }
                    let count = control >= 0 ? control + 1 : 1 - control
                    guard count <= descriptor.width - produced % descriptor.width,
                          count <= pixels - produced else { throw CodecError(.malformedInput, "Packet crosses row or output extent.") }
                    let payload = control >= 0 ? count : 1
                    guard payload <= range.upperBound - cursor else { throw CodecError(.malformedInput, "Truncated packet payload.") }
                    for n in 0..<count {
                        let pixel = produced + n
                        let target = (reference
                            ? location(descriptor, component: component, x: pixel % descriptor.width, y: pixel / descriptor.width)
                            : addressing.offset + (pixel / descriptor.width) * addressing.rowBytes + (pixel % descriptor.width) * addressing.pixelStride) + byteLane
                        out[target] = bytes[cursor + (control >= 0 ? n : 0)]
                        if canonical, lane == bytesPerSample - 1, descriptor.meaningfulBits < descriptor.storageBits {
                            let p = target - byteLane
                            let old = bytesPerSample == 1 ? UInt32(out[p]) : UInt32(try loadUInt16(UnsafeRawBufferPointer(out), at: p, order: descriptor.byteOrder))
                            let mask = (UInt32(1) << descriptor.meaningfulBits) - 1
                            var value = old & mask
                            if descriptor.sampleType == .signedInteger, value & (UInt32(1) << (descriptor.meaningfulBits-1)) != 0 {
                                value |= (bytesPerSample == 1 ? 255 : 65535) ^ mask
                            }
                            normalized = normalized || value != old
                            if bytesPerSample == 1 { out[p] = UInt8(value) }
                            else { try storeUInt16(UInt16(value), into: out, at: p, order: descriptor.byteOrder) }
                        }
                    }
                    cursor += payload; produced += count
                }
                var nops = 0
                while cursor < range.upperBound, bytes[cursor] == 128 {
                    cursor += 1; nops += 1; operations += 1
                    guard nops <= 64, operations <= budget else { throw CodecError(.resourceLimitExceeded, "Trailing NOP budget exceeded.") }
                    try gate.check()
                }
                let padding = (cursor - range.lowerBound) % 2
                guard range.upperBound - cursor == padding,
                      padding == 0 || bytes[cursor] == 0 else { throw CodecError(.malformedInput, "Unexplained trailing segment bytes or nonzero padding.") }
            }
        }
    }

    static func encode(_ image: Image, configuration: EncoderConfiguration, options: EncodeOptions) throws -> EncodedImage {
        let gate = FrameGate(options.resourceLimits)
        try gate.check()
        let frame = try RLEFrameDescriptor(imageDescriptor: image.descriptor, limits: options.resourceLimits)
        if let configured = configuration.codecOptions.frameDescriptor {
            try compatible(configured.imageDescriptor, image.descriptor)
        }
        let metadata = try image.metadata.validate(limits: options.resourceLimits, additionalBytes: image.descriptor.iccProfile?.count ?? 0, check: { try gate.check() })
        let rowBound = try checkedAdd(frame.width, (try checkedAdd(frame.width, 2)) / 3)
        let segmentBound = try checkedAdd(checkedMultiply(rowBound, frame.height), 1)
        let bound = try checkedAdd(64, checkedMultiply(segmentBound, frame.expectedSegmentCount))
        guard UInt64(bound) <= UInt64(UInt32.max),
              bound <= options.resourceLimits.maximumCompressedBytes,
              image.storage.byteCount <= options.resourceLimits.maximumDecodedBytes,
              try checkedAdd(checkedAdd(image.storage.byteCount, bound), metadata) <= options.resourceLimits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Encoding worst-case output exceeds admission limits.")
        }
        let resolved = try AccelerationRuntime.resolve(options.executionPolicy)
        if !image.metadata.entries.isEmpty || image.descriptor.iccProfile != nil {
            guard let external = configuration.codecOptions.frameDescriptor,
                  try external.metadata.equivalent(to: image.metadata, check: { try gate.check() }),
                  external.imageDescriptor.iccProfile == image.descriptor.iccProfile else {
                throw CodecError(.unsupportedFeature, "Preserving frame metadata requires an external descriptor carrying it.")
            }
        }
        options.progress?(try ProgressUpdate(phase: .inspecting, completedUnits: 0, totalUnits: frame.expectedSegmentCount))
        try gate.check()

        let pixels = frame.width * frame.height
        if resolved.backend == .accelerated && !(frame.width == 1 && frame.height == 1) {
            return try encodeAccelerated(
                image: image,
                frame: frame,
                rowBound: rowBound,
                pixels: pixels,
                options: options,
                resolved: resolved,
                gate: gate
            )
        }

        // Scalar reference path (`resolved.backend == .scalarCPU` or 1x1 singleton)
        var out = Data(count: 64)
        out.reserveCapacity(bound)
        func setWord(_ value: Int, _ slot: Int) throws {
            guard let word = UInt32(exactly: value) else { throw CodecError(.resourceLimitExceeded, "Frame offset exceeds UInt32.") }
            for n in 0..<4 { out[slot*4+n] = UInt8(truncatingIfNeeded: word >> (8*n)) }
        }
        try setWord(frame.expectedSegmentCount, 0)
        try image.storage.withUnsafeBytes { bytes in
            guard bytes.count == image.storage.byteCount, bytes.count >= image.descriptor.requiredByteCount else { throw CodecError(.storageUnavailable, "Inconsistent source borrow.") }
            for segment in 0..<frame.expectedSegmentCount {
                try setWord(out.count, segment+1)
                let start = out.count
                let component = segment / frame.bytesPerSample, lane = segment % frame.bytesPerSample
                let reference = usesReferenceAddressing(options.executionPolicy, descriptor: image.descriptor)
                let addressing = try reference ? ComponentAddressing.reference : ComponentAddressing(image.descriptor, component: component)
                for y in 0..<frame.height {
                    func sample(_ x: Int) throws -> UInt16 {
                        let p = reference ? location(image.descriptor, component: component, x: x, y: y)
                            : addressing.offset + y * addressing.rowBytes + x * addressing.pixelStride
                        let order = SharedPathMutation.active == .wrongByteOrder ? image.descriptor.byteOrder.opposite : image.descriptor.byteOrder
                        let value = frame.storageBits == 8 ? UInt16(bytes[p]) : try loadUInt16(bytes, at: p, order: order)
                        let mask = (UInt32(1) << frame.meaningfulBits) - 1
                        var canonical = UInt32(value) & mask
                        if frame.sampleType == .signedInteger, canonical & (UInt32(1) << (frame.meaningfulBits-1)) != 0 {
                            canonical |= (frame.storageBits == 8 ? 255 : 65535) ^ mask
                        }
                        guard canonical == UInt32(value) else { throw CodecError(.invalidArgument, "Noncanonical Image sample exceeds meaningful precision.") }
                        return value
                    }
                    func byte(_ x: Int) throws -> UInt8 { UInt8(truncatingIfNeeded: try sample(x) >> (8 * (frame.bytesPerSample - 1 - lane))) }
                    var x = 0
                    while x < frame.width {
                        try gate.check()
                        let value = try byte(x)
                        var count = 1
                        while count < 128, x+count < frame.width, try byte(x+count) == value { count += 1 }
                        if count >= 2 {
                            out.append(UInt8(bitPattern: Int8(1-count))); out.append(value); x += count
                        } else {
                            let begin = x
                            x += 1
                            while x < frame.width, x-begin < 128 {
                                if x+1 < frame.width, try byte(x) == byte(x+1) { break }
                                x += 1
                            }
                            out.append(UInt8(x-begin-1))
                            for i in begin..<x { out.append(try byte(i)) }
                        }
                    }
                }
                if (out.count-start) % 2 != 0 { out.append(0) }
                options.progress?(try ProgressUpdate(phase: .processing, completedUnits: segment+1, totalUnits: frame.expectedSegmentCount))
            }
        }
        try gate.check()
        options.progress?(try ProgressUpdate(phase: .completed, completedUnits: frame.expectedSegmentCount, totalUnits: frame.expectedSegmentCount))
        try gate.check()
        return EncodedImage(
            data: out,
            encoding: EncodingDescription(format: "dicom-rle", mode: .lossless),
            report: report(backend: resolved.backend, capacity: image.storage.byteCount, allocations: 0, fallback: resolved.fallbackReason)
        )
    }

    private static func encodeAccelerated(
        image: Image,
        frame: RLEFrameDescriptor,
        rowBound: Int,
        pixels: Int,
        options: EncodeOptions,
        resolved: AccelerationRuntime.ResolvedExecution,
        gate: FrameGate
    ) throws -> EncodedImage {
        let segmentCount = frame.expectedSegmentCount
        let maxWorkers = options.resourceLimits.maximumWorkers
        var segmentAddressings: [ComponentAddressing] = []
        segmentAddressings.reserveCapacity(segmentCount)
        for segment in 0..<segmentCount {
            let component = segment / frame.bytesPerSample
            segmentAddressings.append(try ComponentAddressing(image.descriptor, component: component))
        }
        let immutableAddressings = segmentAddressings
        let effectiveOrder = SharedPathMutation.active == .wrongByteOrder ? image.descriptor.byteOrder.opposite : image.descriptor.byteOrder

        let stripsPerSegment = (frame.height >= 16 && pixels >= 4096 && maxWorkers > 1)
            ? min(frame.height, max(1, (maxWorkers * 2 + segmentCount - 1) / segmentCount))
            : 1
        let totalJobs = segmentCount * stripsPerSegment
        let rowsPerStrip = (frame.height + stripsPerSegment - 1) / stripsPerSegment
        let chunksMutex = Mutex<[[UInt8]]>([[UInt8]](repeating: [], count: totalJobs))

        try image.storage.withUnsafeBytes { bytes in
            guard bytes.count == image.storage.byteCount,
                  bytes.count >= image.descriptor.requiredByteCount,
                  let rawBase = bytes.baseAddress else {
                throw CodecError(.storageUnavailable, "Inconsistent source borrow.")
            }
            let sendableSrc = UnsafeSendableRawPointer(baseAddress: rawBase, count: bytes.count)

            try BoundedParallelPool.forEach(jobCount: totalJobs, maxWorkers: maxWorkers) { job in
                let segment = job / stripsPerSegment
                let strip = job % stripsPerSegment
                let yStart = strip * rowsPerStrip
                let yEnd = min(frame.height, yStart + rowsPerStrip)
                guard yStart < yEnd else { return }

                let lane = segment % frame.bytesPerSample
                let addr = immutableAddressings[segment]
                let srcBuf = UnsafeRawBufferPointer(start: sendableSrc.baseAddress, count: sendableSrc.count)
                let srcU8 = sendableSrc.baseAddress.assumingMemoryBound(to: UInt8.self)
                let directContiguous8 = (frame.storageBits == 8 && frame.meaningfulBits == 8 && addr.pixelStride == 1)

                let stripRows = yEnd - yStart
                let maxStripBytes = max(16, rowBound * stripRows)
                let stripOut = try [UInt8](unsafeUninitializedCapacity: maxStripBytes) { dstBuf, initializedCount in
                    let dstBase = dstBuf.baseAddress!
                    var writePos = 0
                    if directContiguous8 {
                        for y in yStart..<yEnd {
                            if ((y - yStart) & 63) == 0 {
                                try gate.check()
                            }
                            let rowStart = addr.offset + y * addr.rowBytes
                            let nEncoded = try SIMDPackBits.encodeContiguousRow(
                                src: srcU8.advanced(by: rowStart),
                                count: frame.width,
                                dst: dstBase.advanced(by: writePos),
                                periodicCheck: { try gate.check() }
                            )
                            writePos += nEncoded
                        }
                    } else {
                        var laneScratch = [UInt8](repeating: 0, count: frame.width)
                        try laneScratch.withUnsafeMutableBufferPointer { laneBuf in
                            let lanePtr = laneBuf.baseAddress!
                            for y in yStart..<yEnd {
                                if ((y - yStart) & 63) == 0 {
                                    try gate.check()
                                }
                                let rowStart = addr.offset + y * addr.rowBytes
                                try SIMDPackBits.gatherRowLane(
                                    bytes: srcBuf,
                                    rowOffset: rowStart,
                                    width: frame.width,
                                    pixelStride: addr.pixelStride,
                                    storageBits: frame.storageBits,
                                    meaningfulBits: frame.meaningfulBits,
                                    sampleType: frame.sampleType,
                                    effectiveOrder: effectiveOrder,
                                    lane: lane,
                                    laneBuffer: lanePtr
                                )
                                let nEncoded = try SIMDPackBits.encodeContiguousRow(
                                    src: lanePtr,
                                    count: frame.width,
                                    dst: dstBase.advanced(by: writePos),
                                    periodicCheck: { try gate.check() }
                                )
                                writePos += nEncoded
                            }
                        }
                    }
                    initializedCount = writePos
                }

                chunksMutex.withLock { $0[job] = stripOut }
            }
        }

        let chunks = chunksMutex.withLock { $0 }
        var segmentOffsets = [Int](repeating: 0, count: segmentCount)
        var segmentRawLengths = [Int](repeating: 0, count: segmentCount)
        var totalSize = 64
        for segment in 0..<segmentCount {
            segmentOffsets[segment] = totalSize
            var segLen = 0
            for strip in 0..<stripsPerSegment {
                segLen += chunks[segment * stripsPerSegment + strip].count
            }
            segmentRawLengths[segment] = segLen
            totalSize += segLen + (segLen % 2)
        }
        guard UInt64(totalSize) <= UInt64(UInt32.max),
              totalSize <= options.resourceLimits.maximumCompressedBytes else {
            throw CodecError(.resourceLimitExceeded, "Encoded RLE frame exceeds compressed limit.")
        }

        var out = Data(count: totalSize)
        out.withUnsafeMutableBytes { rawOut in
            let dst = rawOut.baseAddress!.assumingMemoryBound(to: UInt8.self)
            func writeLE32(_ value: UInt32, slot: Int) {
                let p = slot * 4
                dst[p]     = UInt8(truncatingIfNeeded: value)
                dst[p + 1] = UInt8(truncatingIfNeeded: value >> 8)
                dst[p + 2] = UInt8(truncatingIfNeeded: value >> 16)
                dst[p + 3] = UInt8(truncatingIfNeeded: value >> 24)
            }
            writeLE32(UInt32(segmentCount), slot: 0)
            for segment in 0..<segmentCount {
                writeLE32(UInt32(segmentOffsets[segment]), slot: segment + 1)
                var writePos = segmentOffsets[segment]
                for strip in 0..<stripsPerSegment {
                    let chunk = chunks[segment * stripsPerSegment + strip]
                    if !chunk.isEmpty {
                        chunk.withUnsafeBufferPointer { buf in
                            dst.advanced(by: writePos).update(from: buf.baseAddress!, count: buf.count)
                        }
                        writePos += chunk.count
                    }
                }
                if segmentRawLengths[segment] % 2 != 0 {
                    dst[writePos] = 0
                }
            }
        }

        for segment in 0..<segmentCount {
            options.progress?(try ProgressUpdate(phase: .processing, completedUnits: segment + 1, totalUnits: segmentCount))
            try gate.check()
        }
        options.progress?(try ProgressUpdate(phase: .completed, completedUnits: segmentCount, totalUnits: segmentCount))
        try gate.check()

        return EncodedImage(
            data: out,
            encoding: EncodingDescription(format: "dicom-rle", mode: .lossless),
            report: report(backend: resolved.backend, capacity: image.storage.byteCount, allocations: 0, fallback: resolved.fallbackReason)
        )
    }

    static func compatible(_ a: ImageDescriptor, _ b: ImageDescriptor) throws {
        guard a.width == b.width, a.height == b.height, a.sampleType == b.sampleType,
              a.storageBits == b.storageBits, a.meaningfulBits == b.meaningfulBits,
              a.components == b.components, a.colour == b.colour, a.iccProfile == b.iccProfile else {
            throw CodecError(.incompatibleImageLayout, "Frame and destination sample semantics disagree.")
        }
    }
}

struct FrameGate {
    let deadline: ContinuousClock.Instant
    init(_ limits: ResourceLimits) {
        deadline = ContinuousClock().now.advanced(by: .nanoseconds(Int64(limits.deadlineSeconds * 1_000_000_000)))
    }
    func check() throws {
        try Task.checkCancellation()
        guard ContinuousClock().now <= deadline else { throw CodecError(.resourceLimitExceeded, "Frame deadline exceeded.") }
    }
}
