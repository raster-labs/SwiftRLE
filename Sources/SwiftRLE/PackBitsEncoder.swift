// SPDX-License-Identifier: Apache-2.0
// Adapted from raster-labs/DICOMKit @ 4b68d7e22829418c88e48dd53d98b25fee50d90d (Sources/DICOMCore/RLECodec.swift, MIT)
import Foundation

/// Result of standalone PackBits byte-stream or row-constrained encoding (API-13).
/// Raw byte operations do not invent 2D image dimensions.
public struct EncodedBytes: Sendable, Equatable {
    public let data: Data
    public let encoding: EncodingDescription
    public let report: OperationReport

    public init(
        data: Data,
        encoding: EncodingDescription = EncodingDescription(format: RLEProfile.packBits.rawValue, mode: .lossless),
        report: OperationReport
    ) {
        self.data = data
        self.encoding = encoding
        self.report = report
    }
}

/// Deterministic scalar PackBits byte and row-constrained encoder.
public struct PackBitsEncoder: Sendable {
    public let configuration: EncoderConfiguration

    public static let capabilities = CodecCapabilities(
        formats: [RLEProfile.packBits.rawValue],
        compressionModes: [.lossless],
        sampleTypes: [.unsignedInteger, .signedInteger],
        meaningfulPrecision: 8...8,
        layouts: ["packbits-bytes", "packbits-row-constrained"],
        availableBackends: [.scalarCPU],
        canInspect: false,
        canEncode: true,
        canDecode: false
    )

    public var capabilities: CodecCapabilities { Self.capabilities }

    public init(configuration: EncoderConfiguration = .packBits) throws {
        guard configuration.codecOptions.profile == .packBits,
              configuration.codecOptions.frameDescriptor == nil else {
            throw CodecError(.invalidArgument, "PackBitsEncoder requires the .packBits profile without an RLEFrameDescriptor.")
        }
        self.configuration = configuration
    }

    /// Computes the checked worst-case PackBits output size in bytes for `byteCount` input bytes.
    /// Each row of length `L > 0` expands to at most `L + ceil(L / 3)` bytes.
    /// The greedy two-byte repeat policy can split literals more often than once
    /// per 128 bytes. Each nonfinal literal packet consumes at least three input
    /// bytes together with its following repeat, or contains 128 literal bytes.
    /// Repeat packets never expand their input, so this bounds every packetisation.
    public static func worstCaseEncodedByteCount(
        forByteCount byteCount: Int,
        rowBytes: Int? = nil,
        rowCount: Int? = nil
    ) throws -> Int {
        guard byteCount >= 0 else {
            throw CodecError(.invalidArgument, "Input byte count must not be negative.")
        }
        switch (rowBytes, rowCount) {
        case (nil, nil):
            guard byteCount > 0 else { return 0 }
            let overhead = byteCount / 3 + (byteCount % 3 == 0 ? 0 : 1)
            return try checkedAdd(byteCount, overhead)
        case (.some(let rb), .some(let rc)):
            if byteCount == 0 && rb == 0 && rc == 0 {
                return 0
            }
            guard rb > 0, rc > 0 else {
                throw CodecError(.invalidArgument, "rowBytes and rowCount must be positive for non-empty input.")
            }
            let total = try checkedMultiply(rb, rc)
            guard total == byteCount else {
                throw CodecError(.invalidArgument, "Input byte count (\(byteCount)) does not equal rowBytes * rowCount (\(total)).")
            }
            let rowOverhead = rb / 3 + (rb % 3 == 0 ? 0 : 1)
            let rowWorstCase = try checkedAdd(rb, rowOverhead)
            return try checkedMultiply(rowWorstCase, rc)
        default:
            throw CodecError(.invalidArgument, "Both rowBytes and rowCount must be specified together.")
        }
    }

    /// Encodes `data` as a PackBits stream. When `rowBytes` and `rowCount` are supplied,
    /// each row is encoded independently and no literal or repeat run crosses a row boundary.
    public func encode(
        _ data: Data,
        rowBytes: Int? = nil,
        rowCount: Int? = nil,
        options: EncodeOptions = .init()
    ) throws -> EncodedBytes {
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started.advanced(by: .nanoseconds(Int64(options.resourceLimits.deadlineSeconds * 1_000_000_000)))

        try Task.checkCancellation()
        let fallbackReason = try validateExecutionPolicy(options.executionPolicy)

        let inputCount = data.count
        guard inputCount <= options.resourceLimits.maximumDecodedBytes,
              inputCount <= options.resourceLimits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "PackBits input byte count exceeds resource limits.")
        }

        let effectiveRowBytes: Int
        let effectiveRowCount: Int
        switch (rowBytes, rowCount) {
        case (nil, nil):
            effectiveRowBytes = inputCount
            effectiveRowCount = inputCount == 0 ? 0 : 1
        case (.some(let rb), .some(let rc)):
            if inputCount == 0 && rb == 0 && rc == 0 {
                effectiveRowBytes = 0
                effectiveRowCount = 0
            } else {
                guard rb > 0, rc > 0 else {
                    throw CodecError(.invalidArgument, "rowBytes and rowCount must be positive.")
                }
                guard rb <= options.resourceLimits.maximumDimension,
                      rc <= options.resourceLimits.maximumDimension else {
                    throw CodecError(.resourceLimitExceeded, "Row geometry exceeds maximumDimension limit.")
                }
                let expectedTotal = try checkedMultiply(rb, rc)
                guard expectedTotal == inputCount else {
                    throw CodecError(.invalidArgument, "Input byte count (\(inputCount)) does not equal rowBytes * rowCount (\(expectedTotal)).")
                }
                effectiveRowBytes = rb
                effectiveRowCount = rc
            }
        default:
            throw CodecError(.invalidArgument, "Both rowBytes and rowCount must be specified together.")
        }

        // Validate worst-case arithmetic does not overflow Int.
        let worstCase = try Self.worstCaseEncodedByteCount(
            forByteCount: inputCount,
            rowBytes: rowBytes,
            rowCount: rowCount
        )

        let totalUnits = max(1, effectiveRowCount)
        options.progress?(try ProgressUpdate(phase: .inspecting, completedUnits: 0, totalUnits: totalUnits))

        try Task.checkCancellation()
        guard clock.now <= deadline else {
            throw CodecError(.resourceLimitExceeded, "PackBits encode operation exceeded deadline.")
        }
        // Input remains retained throughout encoding. The admission budget covers
        // it together with output, rather than granting each the entire budget.
        let maxCompressed = min(options.resourceLimits.maximumCompressedBytes,
                                options.resourceLimits.maximumMemoryBytes - inputCount)
        let capacity = min(worstCase, maxCompressed)
        var out = Data(count: capacity)
        var written = 0
        try out.withUnsafeMutableBytes { destination in
        try data.withUnsafeBytes { rawBuffer in
            guard rawBuffer.count == inputCount else {
                throw CodecError(.internalFailure, "Inconsistent Data buffer count.")
            }
            guard inputCount > 0, let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }

            for rowIndex in 0..<effectiveRowCount {
                try Task.checkCancellation()
                if clock.now > deadline {
                    throw CodecError(.resourceLimitExceeded, "PackBits encode operation exceeded deadline.")
                }

                let rowStart = rowIndex * effectiveRowBytes
                let rowEnd = rowStart + effectiveRowBytes
                try Self.encodeRow(
                    base: base,
                    from: rowStart,
                    to: rowEnd,
                    destination: destination,
                    written: &written,
                    maxCompressedBytes: capacity,
                    clock: clock,
                    deadline: deadline
                )

                if effectiveRowCount <= 8 || (rowIndex + 1) % max(1, effectiveRowCount / 8) == 0 {
                    options.progress?(try ProgressUpdate(
                        phase: .processing,
                        completedUnits: rowIndex + 1,
                        totalUnits: totalUnits
                    ))
                }
            }
        }

        }
        out.removeSubrange(written..<out.count)

        try Task.checkCancellation()
        guard clock.now <= deadline else {
            throw CodecError(.resourceLimitExceeded, "PackBits encode operation exceeded deadline.")
        }
        options.progress?(try ProgressUpdate(phase: .completed, completedUnits: totalUnits, totalUnits: totalUnits))
        try Task.checkCancellation()
        guard clock.now <= deadline else {
            throw CodecError(.resourceLimitExceeded, "PackBits encode operation exceeded deadline.")
        }
        let elapsed = clock.now - started
        let report = OperationReport(
            backend: .scalarCPU,
            fallbackReason: fallbackReason,
            fidelity: .exactSamples,
            copyEvents: [],
            pixelAllocationCount: 0,
            peakPixelBytes: 0,
            peakWorkspaceBytes: 0,
            elapsedSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        )
        return EncodedBytes(data: out, report: report)
    }

    /// Explicit synchronous convenience wrapper (API-03) calling the same scalar kernel.
    public func encodeSynchronously(
        _ data: Data,
        rowBytes: Int? = nil,
        rowCount: Int? = nil,
        options: EncodeOptions = .init()
    ) throws -> EncodedBytes {
        try encode(data, rowBytes: rowBytes, rowCount: rowCount, options: options)
    }

    private static func encodeRow(
        base: UnsafePointer<UInt8>, from start: Int, to end: Int,
        destination: UnsafeMutableRawBufferPointer, written: inout Int,
        maxCompressedBytes: Int, clock: ContinuousClock,
        deadline: ContinuousClock.Instant
    ) throws {
        var i = start
        var packets = 0
        while i < end {
            packets += 1
            if packets & 63 == 0 {
                try Task.checkCancellation()
                guard clock.now <= deadline else {
                    throw CodecError(.resourceLimitExceeded, "PackBits encode operation exceeded deadline.")
                }
            }
            var run = 1
            while run < 128 && run < end - i && base[i + run] == base[i] { run += 1 }
            // Pairs inside a literal usually cost less when kept in the literal.
            // An isolated final pair has no following literal header to amortize.
            if run >= 3 || (run == 2 && (i + 2 == end || (end - i >= 4 && base[i+2] == base[i+3]))) {
                guard 2 <= maxCompressedBytes - written else {
                    throw CodecError(.resourceLimitExceeded, "Encoded PackBits output exceeds compressed byte limit.")
                }
                destination[written] = UInt8(257 - run)
                destination[written + 1] = base[i]
                written += 2
                i += run
            } else {
                let begin = i
                i += run
                let literalEnd = begin + min(128, end - begin)
                while i < literalEnd {
                    // Eight adjacent-byte comparisons per scalar word. The first
                    // marked byte is exact even if subtraction borrows mark later bytes.
                    // Normalizing endianness makes trailingZeroBitCount follow input order.
                    if end - i >= 9 && literalEnd - i >= 8 {
                        let a = UnsafeRawPointer(base.advanced(by: i)).loadUnaligned(as: UInt64.self).littleEndian
                        let b = UnsafeRawPointer(base.advanced(by: i + 1)).loadUnaligned(as: UInt64.self).littleEndian
                        let difference = a ^ b
                        let matches = (difference &- 0x0101010101010101) & ~difference & 0x8080808080808080
                        if matches == 0 {
                            i += 8
                            continue
                        }
                        i += matches.trailingZeroBitCount / 8
                    }
                    if end - i >= 2 && base[i] == base[i+1] {
                        if end - i == 2 || (end - i >= 3 && base[i] == base[i+2]) || (end - i >= 4 && base[i+2] == base[i+3]) { break }
                    }
                    i += 1
                }
                let length = i - begin
                guard length + 1 <= maxCompressedBytes - written else {
                    throw CodecError(.resourceLimitExceeded, "Encoded PackBits output exceeds compressed byte limit.")
                }
                destination[written] = UInt8(length - 1)
                destination.baseAddress!.advanced(by: written + 1).copyMemory(from: base.advanced(by: begin), byteCount: length)
                written += length + 1
            }
        }
    }
}
