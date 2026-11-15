// SPDX-License-Identifier: MIT
// Adapted from raster-labs/DICOMKit @ 4b68d7e22829418c88e48dd53d98b25fee50d90d (Sources/DICOMCore/RLECodec.swift, MIT)
import Foundation

/// Result of standalone PackBits byte-stream or row-constrained decoding (API-13).
/// Raw byte operations do not invent 2D image dimensions.
public struct DecodedBytes: Sendable, Equatable {
    public let data: Data
    public let consumedByteCount: Int
    public let report: OperationReport

    public init(data: Data, consumedByteCount: Int, report: OperationReport) {
        self.data = data
        self.consumedByteCount = consumedByteCount
        self.report = report
    }
}

/// Strict scalar and incremental PackBits decoder with `Int`-widened control arithmetic,
/// sliced-`Data` safety, optional row-boundary enforcement and a bounded packet/NOP work budget.
public struct PackBitsDecoder: Sendable {
    public let configuration: DecoderConfiguration

    public static var capabilities: CodecCapabilities {
        CodecCapabilities(
            formats: [RLEProfile.packBits.rawValue],
            compressionModes: [.lossless],
            sampleTypes: [.unsignedInteger, .signedInteger],
            meaningfulPrecision: 8...8,
            layouts: ["packbits-bytes", "packbits-row-constrained"],
            availableBackends: AccelerationRuntime.availableBackends,
            canInspect: false,
            canEncode: false,
            canDecode: true
        )
    }

    public var capabilities: CodecCapabilities { Self.capabilities }

    public init(configuration: DecoderConfiguration = .packBits) throws {
        guard configuration.codecOptions.profile == .packBits,
              configuration.codecOptions.frameDescriptor == nil else {
            throw CodecError(.invalidArgument, "PackBitsDecoder requires the .packBits profile without an RLEFrameDescriptor.")
        }
        self.configuration = configuration
    }

    /// Computes the maximum permitted packet/control-byte operations for `expectedByteCount`
    /// output bytes before a `0x80` (`-128`) no-op flood is rejected with `.resourceLimitExceeded`.
    public static func maximumPacketOperations(
        forExpectedByteCount expectedByteCount: Int,
        multiplier: Int = 2,
        limits: ResourceLimits = .default
    ) throws -> Int {
        guard expectedByteCount >= 0 else {
            throw CodecError(.invalidArgument, "Expected decoded byte count must not be negative.")
        }
        guard (1...64).contains(multiplier) else {
            throw CodecError(.invalidArgument, "Packet operation multiplier must lie in 1...64.")
        }
        let scaled = try checkedMultiply(expectedByteCount, multiplier)
        let total = try checkedAdd(64, scaled)
        return max(64, min(total, limits.maximumCompressedBytes))
    }

    /// Stateful incremental PackBits decoding session across arbitrary chunk boundaries.
    /// Writes decoded bytes directly into the final output buffer without accumulating raw chunks.
    public struct IncrementalSession: Sendable {
        private enum PendingPacket: Sendable, Equatable {
            case awaitingControl
            case awaitingLiteralBytes(remaining: Int)
            case awaitingRepeatByte(count: Int)
        }

        public let expectedByteCount: Int
        public let rowBytes: Int?
        public let rowCount: Int?
        public let maximumPacketOperations: Int
        private let options: DecodeOptions
        private let resolvedBackend: Backend
        private let fallbackReason: String?
        private let clock: ContinuousClock
        private let started: ContinuousClock.Instant
        private let deadline: ContinuousClock.Instant
        private let maxCompressedBytes: Int
        private var output: Data
        private var writtenBytes = 0
        private var pending: PendingPacket = .awaitingControl
        private var consumedBytes = 0
        private var packetOperations = 0
        private var finished = false

        fileprivate init(
            expectedByteCount: Int,
            rowBytes: Int?,
            rowCount: Int?,
            maximumPacketOperations: Int,
            options: DecodeOptions,
            resolvedBackend: Backend,
            fallbackReason: String?
        ) throws {
            self.expectedByteCount = expectedByteCount
            self.rowBytes = rowBytes
            self.rowCount = rowCount
            self.maximumPacketOperations = maximumPacketOperations
            self.options = options
            self.resolvedBackend = resolvedBackend
            self.fallbackReason = fallbackReason
            self.clock = ContinuousClock()
            self.started = clock.now
            self.deadline = started.advanced(by: .nanoseconds(Int64(options.resourceLimits.deadlineSeconds * 1_000_000_000)))
            self.maxCompressedBytes = min(options.resourceLimits.maximumCompressedBytes,
                                          options.resourceLimits.maximumMemoryBytes - expectedByteCount)
            try Task.checkCancellation()
            self.output = expectedByteCount > 0 ? Data(count: expectedByteCount) : Data()
            options.progress?(try ProgressUpdate(phase: .inspecting, completedUnits: 0, totalUnits: max(1, expectedByteCount)))
        }

        /// Appends a compressed chunk (including a sliced `Data` with non-zero `startIndex`).
        /// Any failure permanently closes this session; partial output is never publishable.
        /// Admission conservatively budgets cumulative compressed bytes plus final output,
        /// even when the caller releases previous chunks.
        public mutating func append(_ chunk: Data) throws {
            guard !finished else {
                throw CodecError(.invalidArgument, "Incremental PackBits session has already finished.")
            }
            do {
                try appendValidated(chunk)
            } catch {
                finished = true
                output = Data()
                throw error
            }
        }

        private mutating func appendValidated(_ chunk: Data) throws {
            try Task.checkCancellation()
            if clock.now > deadline {
                throw CodecError(.resourceLimitExceeded, "PackBits decode operation exceeded deadline.")
            }

            let nextConsumed = try checkedAdd(
                consumedBytes,
                chunk.count,
                category: .resourceLimitExceeded,
                message: "Compressed PackBits input overflowed."
            )
            guard nextConsumed <= maxCompressedBytes else {
                throw CodecError(.resourceLimitExceeded, "Compressed PackBits input exceeds resource limits.")
            }

            try chunk.withUnsafeBytes { rawBuffer in
                guard rawBuffer.count == chunk.count else {
                    throw CodecError(.internalFailure, "Inconsistent Data chunk buffer count.")
                }
                guard chunk.count > 0, let base = rawBuffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return
                }

                let localClock = clock
                let localDeadline = deadline
                let maxPacketOps = maximumPacketOperations
                let expectedBytes = expectedByteCount
                let rb = rowBytes
                var localPending = pending
                var localPacketOps = packetOperations
                var localConsumed = consumedBytes
                var localWritten = writtenBytes

                @inline(__always)
                func checkPacketFit(_ packetOutputCount: Int) throws {
                    let nextOutputCount = try checkedAdd(
                        localWritten,
                        packetOutputCount,
                        category: .malformedInput,
                        message: "PackBits decoded output length overflow."
                    )
                    guard nextOutputCount <= expectedBytes else {
                        throw CodecError(
                            .malformedInput,
                            "PackBits run of \(packetOutputCount) bytes exceeds expected decoded length \(expectedBytes) (at offset \(localWritten))."
                        )
                    }
                    if let rb, rb > 0 {
                        let offsetInRow = localWritten % rb
                        let remainingInRow = rb - offsetInRow
                        guard packetOutputCount <= remainingInRow else {
                            throw CodecError(
                                .malformedInput,
                                "PackBits packet of \(packetOutputCount) bytes crosses row boundary (\(remainingInRow) bytes remaining in \(rb)-byte row)."
                            )
                        }
                    }
                }

                try output.withUnsafeMutableBytes { outRaw in
                    let dstBase = outRaw.baseAddress?.assumingMemoryBound(to: UInt8.self)
                    var index = 0
                    let count = chunk.count
                    while index < count {
                        switch localPending {
                        case .awaitingControl:
                            localPacketOps += 1
                            if (localPacketOps & 255) == 0 {
                                try Task.checkCancellation()
                                if localClock.now > localDeadline {
                                    throw CodecError(.resourceLimitExceeded, "PackBits decode operation exceeded deadline.")
                                }
                            }
                            guard localPacketOps <= maxPacketOps else {
                                throw CodecError(.resourceLimitExceeded, "PackBits packet/NOP operation budget (\(maxPacketOps)) exceeded.")
                            }

                            let rawControl = Int(Int8(bitPattern: base[index]))
                            index += 1
                            localConsumed += 1

                            if rawControl == -128 {
                                continue
                            } else if rawControl >= 0 {
                                let literalCount = rawControl + 1
                                try checkPacketFit(literalCount)
                                if index + literalCount <= count, let dstBase {
                                    dstBase.advanced(by: localWritten).update(from: base.advanced(by: index), count: literalCount)
                                    localWritten += literalCount
                                    index += literalCount
                                    localConsumed += literalCount
                                } else {
                                    localPending = .awaitingLiteralBytes(remaining: literalCount)
                                }
                            } else {
                                let repeatCount = (-rawControl) + 1
                                try checkPacketFit(repeatCount)
                                if index < count, let dstBase {
                                    let value = base[index]
                                    index += 1
                                    localConsumed += 1
                                    dstBase.advanced(by: localWritten).update(repeating: value, count: repeatCount)
                                    localWritten += repeatCount
                                } else {
                                    localPending = .awaitingRepeatByte(count: repeatCount)
                                }
                            }

                        case .awaitingLiteralBytes(let remaining):
                            let available = count - index
                            let copyCount = min(remaining, available)
                            if copyCount > 0, let dstBase {
                                dstBase.advanced(by: localWritten).update(from: base.advanced(by: index), count: copyCount)
                            }
                            localWritten += copyCount
                            index += copyCount
                            localConsumed += copyCount
                            if copyCount == remaining {
                                localPending = .awaitingControl
                            } else {
                                localPending = .awaitingLiteralBytes(remaining: remaining - copyCount)
                            }

                        case .awaitingRepeatByte(let repeatCount):
                            let value = base[index]
                            index += 1
                            localConsumed += 1
                            if repeatCount > 0, let dstBase {
                                dstBase.advanced(by: localWritten).update(repeating: value, count: repeatCount)
                            }
                            localWritten += repeatCount
                            localPending = .awaitingControl
                        }
                    }
                }

                pending = localPending
                packetOperations = localPacketOps
                consumedBytes = localConsumed
                writtenBytes = localWritten
            }
        }

        /// Finalises the incremental session and verifies that no packet was truncated
        /// and that the decoded length matches `expectedByteCount` exactly.
        public mutating func finish() throws -> DecodedBytes {
            guard !finished else {
                throw CodecError(.invalidArgument, "Incremental PackBits session has already finished.")
            }
            finished = true
            defer { output = Data() }
            try Task.checkCancellation()
            if clock.now > deadline {
                throw CodecError(.resourceLimitExceeded, "PackBits decode operation exceeded deadline.")
            }

            switch pending {
            case .awaitingControl:
                break
            case .awaitingLiteralBytes:
                throw CodecError(.malformedInput, "Truncated PackBits literal packet at end of stream.")
            case .awaitingRepeatByte:
                throw CodecError(.malformedInput, "Truncated PackBits repeat packet missing byte value.")
            }

            guard writtenBytes == expectedByteCount else {
                throw CodecError(
                    .malformedInput,
                    "PackBits stream ended after \(writtenBytes) of \(expectedByteCount) expected bytes."
                )
            }

            let totalUnits = max(1, expectedByteCount)
            options.progress?(try ProgressUpdate(phase: .processing, completedUnits: totalUnits, totalUnits: totalUnits))
            try Task.checkCancellation()
            guard clock.now <= deadline else {
                throw CodecError(.resourceLimitExceeded, "PackBits decode operation exceeded deadline.")
            }

            options.progress?(try ProgressUpdate(phase: .completed, completedUnits: totalUnits, totalUnits: totalUnits))
            try Task.checkCancellation()
            guard clock.now <= deadline else {
                throw CodecError(.resourceLimitExceeded, "PackBits decode operation exceeded deadline.")
            }

            let elapsed = clock.now - started
            let report = OperationReport(
                backend: resolvedBackend,
                fallbackReason: fallbackReason,
                fidelity: .exactSamples,
                copyEvents: [],
                pixelAllocationCount: 0,
                peakPixelBytes: 0,
                peakWorkspaceBytes: 0,
                elapsedSeconds: Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
            )
            return DecodedBytes(data: output, consumedByteCount: consumedBytes, report: report)
        }

        private func validatePacketFit(packetOutputCount: Int) throws {
            let nextOutputCount = try checkedAdd(
                writtenBytes,
                packetOutputCount,
                category: .malformedInput,
                message: "PackBits decoded output length overflow."
            )
            guard nextOutputCount <= expectedByteCount else {
                throw CodecError(
                    .malformedInput,
                    "PackBits run of \(packetOutputCount) bytes exceeds expected decoded length \(expectedByteCount) (at offset \(writtenBytes))."
                )
            }
            if let rb = rowBytes, rb > 0 {
                let offsetInRow = writtenBytes % rb
                let remainingInRow = rb - offsetInRow
                guard packetOutputCount <= remainingInRow else {
                    throw CodecError(
                        .malformedInput,
                        "PackBits packet of \(packetOutputCount) bytes crosses row boundary (\(remainingInRow) bytes remaining in \(rb)-byte row)."
                    )
                }
            }
        }
    }

    /// Creates a validated incremental PackBits decoding session.
    public func makeIncrementalSession(
        expectedByteCount: Int,
        rowBytes: Int? = nil,
        rowCount: Int? = nil,
        options: DecodeOptions = .init()
    ) throws -> IncrementalSession {
        try Task.checkCancellation()
        let resolved = try AccelerationRuntime.resolve(options.executionPolicy)
        let fallbackReason = resolved.fallbackReason

        if let callCodecOptions = options.codecOptions {
            guard callCodecOptions.profile == .packBits,
                  callCodecOptions.frameDescriptor == nil else {
                throw CodecError(.invalidArgument, "PackBitsDecoder requires the .packBits profile without an RLEFrameDescriptor.")
            }
        }

        guard expectedByteCount >= 0 else {
            throw CodecError(.invalidArgument, "Expected decoded byte count must not be negative.")
        }
        guard expectedByteCount <= options.resourceLimits.maximumDecodedBytes,
              expectedByteCount <= options.resourceLimits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Expected PackBits decoded byte count exceeds resource limits.")
        }

        let effectiveRowBytes: Int?
        let effectiveRowCount: Int?
        switch (rowBytes, rowCount) {
        case (nil, nil):
            effectiveRowBytes = nil
            effectiveRowCount = nil
        case (.some(let rb), .some(let rc)):
            if expectedByteCount == 0 && rb == 0 && rc == 0 {
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
                guard expectedTotal == expectedByteCount else {
                    throw CodecError(
                        .invalidArgument,
                        "Expected decoded byte count (\(expectedByteCount)) does not equal rowBytes * rowCount (\(expectedTotal))."
                    )
                }
                effectiveRowBytes = rb
                effectiveRowCount = rc
            }
        default:
            throw CodecError(.invalidArgument, "Both rowBytes and rowCount must be specified together.")
        }

        let multiplier = options.codecOptions?.maximumPacketOperationsPerOutputByte
            ?? configuration.codecOptions.maximumPacketOperationsPerOutputByte
        let maxOps = try Self.maximumPacketOperations(
            forExpectedByteCount: expectedByteCount,
            multiplier: multiplier,
            limits: options.resourceLimits
        )

        return try IncrementalSession(
            expectedByteCount: expectedByteCount,
            rowBytes: effectiveRowBytes,
            rowCount: effectiveRowCount,
            maximumPacketOperations: maxOps,
            options: options,
            resolvedBackend: resolved.backend,
            fallbackReason: fallbackReason
        )
    }

    /// Decodes a complete PackBits byte stream or slice (`startIndex != 0`) into `expectedByteCount` bytes.
    public func decode(
        _ data: Data,
        expectedByteCount: Int,
        rowBytes: Int? = nil,
        rowCount: Int? = nil,
        options: DecodeOptions = .init()
    ) throws -> DecodedBytes {
        try validateCompressedAdmission(data.count, expectedByteCount: expectedByteCount, limits: options.resourceLimits)
        var session = try makeIncrementalSession(
            expectedByteCount: expectedByteCount,
            rowBytes: rowBytes,
            rowCount: rowCount,
            options: options
        )
        try session.append(data)
        return try session.finish()
    }

    /// Explicit synchronous convenience wrapper (API-03) calling the same scalar kernel.
    public func decodeSynchronously(
        _ data: Data,
        expectedByteCount: Int,
        rowBytes: Int? = nil,
        rowCount: Int? = nil,
        options: DecodeOptions = .init()
    ) throws -> DecodedBytes {
        try decode(
            data,
            expectedByteCount: expectedByteCount,
            rowBytes: rowBytes,
            rowCount: rowCount,
            options: options
        )
    }

    /// Decodes a sequence of compressed PackBits chunks incrementally and verifies that
    /// the concatenated stream produces `expectedByteCount` bytes without packet truncation.
    public func decodeIncremental<C: Collection>(
        _ chunks: C,
        expectedByteCount: Int,
        rowBytes: Int? = nil,
        rowCount: Int? = nil,
        options: DecodeOptions = .init()
    ) throws -> DecodedBytes where C.Element == Data {
        let clock = ContinuousClock()
        let started = clock.now
        let deadline = started.advanced(by: .nanoseconds(Int64(options.resourceLimits.deadlineSeconds * 1_000_000_000)))
        var compressedCount = 0
        for chunk in chunks {
            try Task.checkCancellation()
            guard clock.now <= deadline else {
                throw CodecError(.resourceLimitExceeded, "PackBits decode operation exceeded deadline.")
            }
            compressedCount = try checkedAdd(compressedCount, chunk.count, category: .resourceLimitExceeded)
            try validateCompressedAdmission(compressedCount, expectedByteCount: expectedByteCount, limits: options.resourceLimits)
        }
        var session = try makeIncrementalSession(
            expectedByteCount: expectedByteCount,
            rowBytes: rowBytes,
            rowCount: rowCount,
            options: options
        )
        for chunk in chunks {
            try session.append(chunk)
        }
        guard clock.now <= deadline else {
            throw CodecError(.resourceLimitExceeded, "PackBits decode operation exceeded deadline.")
        }
        let result = try session.finish()
        try Task.checkCancellation()
        guard clock.now <= deadline else {
            throw CodecError(.resourceLimitExceeded, "PackBits decode operation exceeded deadline.")
        }
        return result
    }

    private func validateCompressedAdmission(_ count: Int, expectedByteCount: Int, limits: ResourceLimits) throws {
        try Task.checkCancellation()
        guard expectedByteCount >= 0 else {
            throw CodecError(.invalidArgument, "Expected decoded byte count must not be negative.")
        }
        guard count <= limits.maximumCompressedBytes,
              expectedByteCount <= limits.maximumDecodedBytes,
              try checkedAdd(count, expectedByteCount, category: .resourceLimitExceeded) <= limits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "PackBits compressed input and decoded output exceed the admission budget.")
        }
    }
}
