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
        let initialReserve = min(worstCase, min(maxCompressed, max(16, inputCount / 2 + 16)))
        var out = Data()
        if inputCount > 0 {
            out.reserveCapacity(initialReserve)
        }

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
                    into: &out,
                    maxCompressedBytes: maxCompressed,
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
        options.progress?(try ProgressUpdate(phase: .completed, completedUnits: totalUnits, totalUnits: totalUnits))
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
        base: UnsafePointer<UInt8>,
        from start: Int,
        to end: Int,
        into out: inout Data,
        maxCompressedBytes: Int,
        clock: ContinuousClock,
        deadline: ContinuousClock.Instant
    ) throws {
        var i = start
        var stepsSinceCheck = 0
        while i < end {
            stepsSinceCheck += 1
            if stepsSinceCheck >= 64 {
                stepsSinceCheck = 0
                try Task.checkCancellation()
                if clock.now > deadline {
                    throw CodecError(.resourceLimitExceeded, "PackBits encode operation exceeded deadline.")
                }
            }

            // Measure a replicate run starting at i (capped at 128 and row boundary `end`).
            var runLength = 1
            while i + runLength < end && base[i + runLength] == base[i] && runLength < 128 {
                runLength += 1
            }

            if runLength >= 2 {
                let nextSize = try checkedAdd(out.count, 2, category: .resourceLimitExceeded, message: "Encoded PackBits output overflowed.")
                guard nextSize <= maxCompressedBytes else {
                    throw CodecError(.resourceLimitExceeded, "Encoded PackBits output exceeds compressed byte limit.")
                }
                let control = UInt8(bitPattern: Int8(-(runLength - 1)))
                out.append(control)
                out.append(base[i])
                i += runLength
            } else {
                // Literal run: copy until a >= 2 identical pair begins, `end`, or 128 bytes.
                let literalStart = i
                var literalLength = 0
                while i < end && literalLength < 128 {
                    if i + 1 < end && base[i] == base[i + 1] {
                        break
                    }
                    i += 1
                    literalLength += 1
                }
                let packetBytes = try checkedAdd(literalLength, 1)
                let nextSize = try checkedAdd(out.count, packetBytes, category: .resourceLimitExceeded, message: "Encoded PackBits output overflowed.")
                guard nextSize <= maxCompressedBytes else {
                    throw CodecError(.resourceLimitExceeded, "Encoded PackBits output exceeds compressed byte limit.")
                }
                let control = UInt8(bitPattern: Int8(literalLength - 1))
                out.append(control)
                out.append(UnsafeBufferPointer(start: base.advanced(by: literalStart), count: literalLength))
            }
        }
    }
}
