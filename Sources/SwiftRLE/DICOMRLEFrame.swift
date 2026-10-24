// SPDX-License-Identifier: Apache-2.0
import Foundation

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
    static let capabilities = CodecCapabilities(formats: ["dicom-rle"], compressionModes: [.lossless],
        sampleTypes: [.unsignedInteger, .signedInteger], meaningfulPrecision: 1...16,
        layouts: [CodecCapabilities.sharedGreyscaleLayout, "8/16-bit-mono-palette", "unsigned-RGB-YBR_FULL-interleaved-planar"],
        availableBackends: [.scalarCPU], canInspect: true, canEncode: true, canDecode: true)

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
        options.progress?(try ProgressUpdate(phase: .inspecting, completedUnits: 0, totalUnits: 1))
        try gate.check()
        let owner = try OwnedImageStorage(byteCount: descriptor.imageDescriptor.requiredByteCount, limits: options.resourceLimits)
        let lease = try owner.reserveWrite()
        do {
            var normalized = false
            try owner.withUnsafeMutableBytes(lease: lease) { out in
                try scatter(data, header: header, descriptor: descriptor.imageDescriptor, out: out,
                            multiplier: options.codecOptions?.maximumPacketOperationsPerOutputByte ?? 2, canonical: false, normalized: &normalized, gate: gate)
            }
            try gate.check()
            let sealed = try owner.finishAndSeal(lease: lease)
            try gate.check()
            options.progress?(try ProgressUpdate(phase: .completed, completedUnits: 1, totalUnits: 1))
            try gate.check()
            return RawAllocatedCells(descriptor: descriptor, storage: sealed,
                report: report(capacity: owner.byteCount, allocations: 1, fallback: try validateExecutionPolicy(options.executionPolicy)))
        } catch { try? owner.abortAndInvalidate(lease: lease); throw error }
    }

    static func report(capacity: Int, allocations: Int, fallback: String?, normalized: Bool = false) -> OperationReport {
        OperationReport(backend: .scalarCPU, fallbackReason: fallback, fidelity: .exactSamples,
                        pixelAllocationCount: allocations, peakPixelBytes: capacity, peakWorkspaceBytes: 0,
                        sampleNormalizations: normalized ? ["Unused allocated bits masked/sign-extended in final output."] : [])
    }

    static func preflight(_ data: Data, descriptor: RLEFrameDescriptor, capacity: Int,
                          options: DecodeOptions, gate: FrameGate) throws -> DICOMRLEHeader {
        try gate.check()
        _ = try validateExecutionPolicy(options.executionPolicy)
        try descriptor.imageDescriptor.validate(limits: options.resourceLimits)
        let metadata = try descriptor.metadata.validate(limits: options.resourceLimits,
                              additionalBytes: descriptor.imageDescriptor.iccProfile?.count ?? 0, check: { try gate.check() })
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

    static func location(_ descriptor: ImageDescriptor, component: Int, x: Int, y: Int) -> Int {
        // Validated descriptors prove all arithmetic and disjoint extents.
        for plane in descriptor.planes {
            if let index = plane.components.firstIndex(of: component) {
                let row = SharedPathMutation.active == .ignoreRowStride ? descriptor.width * plane.pixelStride : plane.rowBytes
                return plane.offset + y * row + x * plane.pixelStride + index * plane.sampleStride
            }
        }
        return 0 // Constructor guarantees every component is mapped exactly once.
    }

    static func scatter(_ data: Data, header: DICOMRLEHeader, descriptor: ImageDescriptor,
                        out: UnsafeMutableRawBufferPointer, multiplier: Int, canonical: Bool, normalized: inout Bool, gate: FrameGate) throws {
        guard out.count >= descriptor.requiredByteCount else { throw CodecError(.storageUnavailable, "Short destination borrow.") }
        let bytesPerSample = descriptor.storageBits / 8
        let pixels = try checkedMultiply(descriptor.width, descriptor.height)
        let budget = try checkedAdd(64, checkedMultiply(pixels, multiplier))
        try data.withUnsafeBytes { bytes in
            for (segment, range) in header.segmentRanges.enumerated() {
                let component = segment / bytesPerSample, lane = segment % bytesPerSample
                let order = SharedPathMutation.active == .wrongByteOrder ? descriptor.byteOrder.opposite : descriptor.byteOrder
                let byteLane = order == .bigEndian ? lane : bytesPerSample - 1 - lane
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
                        let target = location(descriptor, component: component, x: pixel % descriptor.width, y: pixel / descriptor.width) + byteLane
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
                // At most 64 trailing NOPs, followed by exactly the zero pad
                // required for odd packet length. No arbitrary trailing payload.
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
        // Conservative deterministic two-byte-repeat bound, matching PackBits R1.
        let rowBound = try checkedAdd(frame.width, (try checkedAdd(frame.width, 2)) / 3)
        let segmentBound = try checkedAdd(checkedMultiply(rowBound, frame.height), 1)
        let bound = try checkedAdd(64, checkedMultiply(segmentBound, frame.expectedSegmentCount))
        guard UInt64(bound) <= UInt64(UInt32.max),
              bound <= options.resourceLimits.maximumCompressedBytes,
              image.storage.byteCount <= options.resourceLimits.maximumDecodedBytes,
              try checkedAdd(checkedAdd(image.storage.byteCount, bound), metadata) <= options.resourceLimits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Encoding worst-case output exceeds admission limits.")
        }
        let fallback = try validateExecutionPolicy(options.executionPolicy)
        // A frame header cannot carry image metadata. Require the caller's
        // external descriptor to retain required semantics, rather than drop it.
        if !image.metadata.entries.isEmpty || image.descriptor.iccProfile != nil {
            guard let external = configuration.codecOptions.frameDescriptor,
                  try external.metadata.equivalent(to: image.metadata, check: { try gate.check() }),
                  external.imageDescriptor.iccProfile == image.descriptor.iccProfile else {
                throw CodecError(.unsupportedFeature, "Preserving frame metadata requires an external descriptor carrying it.")
            }
        }
        options.progress?(try ProgressUpdate(phase: .inspecting, completedUnits: 0, totalUnits: frame.expectedSegmentCount))
        try gate.check()
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
                for y in 0..<frame.height {
                    func sample(_ x: Int) throws -> UInt16 {
                        let p = location(image.descriptor, component: component, x: x, y: y)
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
        return EncodedImage(data: out, encoding: EncodingDescription(format: "dicom-rle", mode: .lossless), report: report(capacity: image.storage.byteCount, allocations: 0, fallback: fallback))
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
