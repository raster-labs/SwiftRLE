// SPDX-License-Identifier: Apache-2.0
import Foundation

public struct EncoderConfiguration: Sendable, Equatable {
    public let mode: CompressionMode
    public let codecOptions: CodecOptions

    public init(mode: CompressionMode = .lossless, codecOptions: CodecOptions = .init()) throws {
        if case .nearLossless(let bound) = mode, bound <= 0 {
            throw CodecError(.invalidArgument, "Near-lossless error must be positive.")
        }
        guard mode == .lossless else {
            throw CodecError(.unsupportedFeature, "Only lossless encoding is supported by RLE; lossy and near-lossless modes are not available.")
        }
        self.mode = mode
        self.codecOptions = codecOptions
    }

    private init(validatedCodecOptions: CodecOptions) {
        self.mode = .lossless
        self.codecOptions = validatedCodecOptions
    }

    public static let `default` = Self(validatedCodecOptions: .dicomRLEFrame)
    public static let packBits = Self(validatedCodecOptions: .packBits)
}

public struct DecoderConfiguration: Sendable, Equatable {
    public let codecOptions: CodecOptions
    public init(codecOptions: CodecOptions = .init()) {
        self.codecOptions = codecOptions
    }
    public static let `default` = Self(codecOptions: .dicomRLEFrame)
    public static let packBits = Self(codecOptions: .packBits)
}

public struct CodecCapabilities: Sendable, Equatable {
    public let formats: [String]
    public let compressionModes: [CompressionMode]
    public let sampleTypes: [SampleType]
    public let meaningfulPrecision: ClosedRange<Int>?
    public let layouts: [String]
    public let availableBackends: [Backend]
    public let canInspect: Bool
    public let canEncode: Bool
    public let canDecode: Bool

    public init(
        formats: [String],
        compressionModes: [CompressionMode],
        sampleTypes: [SampleType],
        meaningfulPrecision: ClosedRange<Int>?,
        layouts: [String],
        availableBackends: [Backend],
        canInspect: Bool,
        canEncode: Bool,
        canDecode: Bool
    ) {
        self.formats = formats
        self.compressionModes = compressionModes
        self.sampleTypes = sampleTypes
        self.meaningfulPrecision = meaningfulPrecision
        self.layouts = layouts
        self.availableBackends = availableBackends
        self.canInspect = canInspect
        self.canEncode = canEncode
        self.canDecode = canDecode
    }

    public static let contractOnly = Self(
        formats: [],
        compressionModes: [],
        sampleTypes: [],
        meaningfulPrecision: nil,
        layouts: [],
        availableBackends: [],
        canInspect: false,
        canEncode: false,
        canDecode: false
    )

    /// The shared layout every operation accepts: MEM-03 with 16-bit storage.
    public static let sharedGreyscaleLayout = "unsigned-greyscale-16bit-single-plane"
}

public struct CopyEvent: Sendable, Equatable {
    public let reason: String
    public let bytesMoved: Int
    public let sourceLayout: String
    public let destinationLayout: String
    public init(reason: String, bytesMoved: Int, sourceLayout: String, destinationLayout: String) throws {
        guard bytesMoved >= 0 else { throw CodecError(.invalidArgument, "Copy byte count must not be negative.") }
        self.reason = reason; self.bytesMoved = bytesMoved
        self.sourceLayout = sourceLayout; self.destinationLayout = destinationLayout
    }
}

public enum Fidelity: Sendable, Equatable { case exactSamples, boundedError(Int), lossy, originalBitstream }

public struct OperationReport: Sendable, Equatable {
    public let backend: Backend
    public let fallbackReason: String?
    public let fidelity: Fidelity
    public let copyEvents: [CopyEvent]
    public let pixelAllocationCount: Int?
    public let peakPixelBytes: Int?
    public let peakWorkspaceBytes: Int?
    public let elapsedSeconds: Double?
    public let sampleNormalizations: [String]
    public init(backend: Backend, fallbackReason: String? = nil, fidelity: Fidelity,
                copyEvents: [CopyEvent] = [], pixelAllocationCount: Int? = nil,
                peakPixelBytes: Int? = nil, peakWorkspaceBytes: Int? = nil, elapsedSeconds: Double? = nil, sampleNormalizations: [String] = []) {
        self.backend = backend; self.fallbackReason = fallbackReason; self.fidelity = fidelity
        self.copyEvents = copyEvents; self.pixelAllocationCount = pixelAllocationCount
        self.peakPixelBytes = peakPixelBytes; self.peakWorkspaceBytes = peakWorkspaceBytes
        self.elapsedSeconds = elapsedSeconds
        self.sampleNormalizations = sampleNormalizations
    }
}

public struct ImageInfo: Sendable, Equatable {
    public let format: String
    public let descriptor: ImageDescriptor
    public let frameCount: Int
    public let metadata: ImageMetadata
    public init(format: String, descriptor: ImageDescriptor, frameCount: Int, metadata: ImageMetadata) {
        self.format = format
        self.descriptor = descriptor
        self.frameCount = frameCount
        self.metadata = metadata
    }
}

public struct EncodingDescription: Sendable, Equatable {
    public let format: String
    public let mode: CompressionMode
    public init(format: String, mode: CompressionMode) {
        self.format = format
        self.mode = mode
    }
}

public struct EncodedImage: Sendable {
    public let data: Data
    public let encoding: EncodingDescription
    public let report: OperationReport
    public init(data: Data, encoding: EncodingDescription, report: OperationReport) {
        self.data = data
        self.encoding = encoding
        self.report = report
    }
}

public struct DecodedImage: Sendable {
    public let image: Image
    public let report: OperationReport
    public init(image: Image, report: OperationReport) {
        self.image = image
        self.report = report
    }
}

/// Image-level strict DICOM RLE encoder using direct strided byte-lane reads.
public struct Encoder: Sendable {
    public let configuration: EncoderConfiguration
    public static let capabilities: CodecCapabilities = DICOMRLEFrame.capabilities
    public var capabilities: CodecCapabilities { Self.capabilities }

    public init(configuration: EncoderConfiguration = .default) throws {
        guard configuration.codecOptions.profile == .dicomRLEFrame else {
            throw CodecError(
                .invalidArgument,
                "Image-level Encoder requires the .dicomRLEFrame profile; use PackBitsEncoder for raw PackBits byte streams."
            )
        }
        self.configuration = configuration
    }

    /// `@concurrent` explicitly selects the generic executor (available since Swift 6.2).
    @concurrent public func encode(_ image: Image, options: EncodeOptions = .init()) async throws -> EncodedImage {
        try encodeSynchronously(image, options: options)
    }

    /// Explicit synchronous convenience wrapper (API-03) calling the same validated kernel.
    public func encodeSynchronously(_ image: Image, options: EncodeOptions = .init()) throws -> EncodedImage {
        try DICOMRLEFrame.encode(image, configuration: configuration, options: options)
    }
}

/// Image-level strict DICOM RLE decoder using one shared final-output kernel.
public struct Decoder: Sendable {
    public let configuration: DecoderConfiguration
    public static let capabilities: CodecCapabilities = DICOMRLEFrame.capabilities
    public var capabilities: CodecCapabilities { Self.capabilities }

    public init(configuration: DecoderConfiguration = .init()) throws {
        guard configuration.codecOptions.profile == .dicomRLEFrame else {
            throw CodecError(
                .invalidArgument,
                "Image-level Decoder requires the .dicomRLEFrame profile; use PackBitsDecoder for raw PackBits byte streams."
            )
        }
        self.configuration = configuration
    }

    /// Resolves effective `RLEFrameDescriptor` across `DecodeOptions.codecOptions` and
    /// `DecoderConfiguration.codecOptions`, validating profile and descriptor conflicts.
    func resolveFrameDescriptor(
        for options: DecodeOptions,
        destinationDescriptor: ImageDescriptor? = nil,
        check: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> RLEFrameDescriptor {
        try check()
        if let callOptions = options.codecOptions {
            guard callOptions.profile == .dicomRLEFrame else {
                throw CodecError(
                    .invalidArgument,
                    "Image-level Decoder requires the .dicomRLEFrame profile; use PackBitsDecoder for raw PackBits byte streams."
                )
            }
            if let callDesc = callOptions.frameDescriptor,
               let configDesc = configuration.codecOptions.frameDescriptor,
               try !callDesc.equivalent(to: configDesc, check: check) {
                throw CodecError(
                    .invalidArgument,
                    "DecodeOptions.codecOptions.frameDescriptor conflicts with DecoderConfiguration.codecOptions.frameDescriptor."
                )
            }
        }
        guard let resolved = options.codecOptions?.frameDescriptor ?? configuration.codecOptions.frameDescriptor else {
            throw CodecError(
                .invalidArgument,
                "DICOM RLE frame operations require an explicit RLEFrameDescriptor in DecodeOptions.codecOptions or DecoderConfiguration.codecOptions."
            )
        }
        try resolved.imageDescriptor.validate(limits: options.resourceLimits)
        if let dest = destinationDescriptor {
            try dest.validate(limits: options.resourceLimits)
            guard dest.width == resolved.width,
                  dest.height == resolved.height,
                  dest.sampleType == resolved.sampleType,
                  dest.storageBits == resolved.storageBits,
                  dest.meaningfulBits == resolved.meaningfulBits,
                  dest.components == resolved.components,
                  dest.colour == resolved.colour else {
                throw CodecError(.incompatibleImageLayout, "Destination ImageDescriptor does not match the resolved RLEFrameDescriptor.")
            }
        }
        return resolved
    }

    public func inspect(_ data: Data, options: DecodeOptions = .init()) throws -> ImageInfo {
        let gate = FrameGate(options.resourceLimits)
        let frame = try resolveFrameDescriptor(for: options, check: { try gate.check() })
        _ = try DICOMRLEFrame.preflight(data, descriptor: frame, capacity: 0, options: options, gate: gate)
        try gate.check()
        return ImageInfo(format: "dicom-rle", descriptor: frame.imageDescriptor, frameCount: 1, metadata: frame.metadata)
    }

    @concurrent public func decode(_ data: Data, options: DecodeOptions = .init()) async throws -> DecodedImage {
        try decodeSynchronously(data, options: options)
    }

    @concurrent public func decode(
        _ data: Data,
        into destination: ImageDestination,
        options: DecodeOptions = .init()
    ) async throws -> DecodedImage {
        try decodeSynchronously(data, into: destination, options: options)
    }

    /// Explicit synchronous convenience wrapper (API-03) calling the same validated kernel.
    public func decodeSynchronously(_ data: Data, options: DecodeOptions = .init()) throws -> DecodedImage {
        let gate = FrameGate(options.resourceLimits)
        let frame = try resolveFrameDescriptor(for: options, check: { try gate.check() })
        _ = try DICOMRLEFrame.preflight(data, descriptor: frame, capacity: frame.imageDescriptor.requiredByteCount, options: options, gate: gate)
        try gate.check()
        let destination = try ImageDestination.allocate(descriptor: frame.imageDescriptor, limits: options.resourceLimits)
        return try decodeFrame(data, into: destination, options: options, allocations: 1, gate: gate)
    }

    /// Explicit synchronous convenience wrapper (API-03) calling the same validated kernel.
    /// Preflight rejections leave `destination` reusable without invalidating its reservation.
    public func decodeSynchronously(
        _ data: Data,
        into destination: ImageDestination,
        options: DecodeOptions = .init()
    ) throws -> DecodedImage {
        try decodeFrame(data, into: destination, options: options, allocations: 0, gate: FrameGate(options.resourceLimits))
    }
    private func decodeFrame(_ data: Data, into destination: ImageDestination, options: DecodeOptions,
                             allocations: Int, gate: FrameGate) throws -> DecodedImage {
        let frame = try resolveFrameDescriptor(for: options, destinationDescriptor: destination.descriptor, check: { try gate.check() })
        _ = try RLEFrameDescriptor(imageDescriptor: destination.descriptor, limits: options.resourceLimits)
        try DICOMRLEFrame.compatible(frame.imageDescriptor, destination.descriptor)
        let header = try DICOMRLEFrame.preflight(data, descriptor: frame, capacity: destination.storage.byteCount, options: options, gate: gate)
        let fallback = try validateExecutionPolicy(options.executionPolicy)
        options.progress?(try ProgressUpdate(phase: .inspecting, completedUnits: 0, totalUnits: 1))
        try gate.check()
        var normalized = false
        let image = try destination.writeValidated(metadata: frame.metadata, validate: { try gate.check() }, admissionCheck: { try gate.check() }) { bytes in
            try DICOMRLEFrame.scatter(data, header: header, descriptor: destination.descriptor, out: bytes,
                multiplier: options.codecOptions?.maximumPacketOperationsPerOutputByte ?? configuration.codecOptions.maximumPacketOperationsPerOutputByte,
                canonical: true, normalized: &normalized, gate: gate)
            try gate.check()
        }
        try gate.check()
        options.progress?(try ProgressUpdate(phase: .completed, completedUnits: 1, totalUnits: 1))
        try gate.check()
        return DecodedImage(image: image, report: DICOMRLEFrame.report(capacity: destination.storage.byteCount,
            allocations: allocations, fallback: fallback, normalized: normalized))
    }

}

@discardableResult
func validateExecutionPolicy(_ policy: ExecutionPolicy) throws -> String? {
    switch policy {
    case .automatic, .scalarCPU, .preferred(.scalarCPU), .required(.scalarCPU):
        return nil
    case .preferred(.accelerated):
        return "Accelerated backend is not implemented; using scalarCPU."
    case .required(.accelerated):
        throw CodecError(.backendUnavailable, "No accelerated backend is implemented.")
    }
}

private func validateInput(_ data: Data, _ options: DecodeOptions) throws {
    _ = try validateExecutionPolicy(options.executionPolicy)
    guard data.count <= options.resourceLimits.maximumCompressedBytes,
          data.count <= options.resourceLimits.maximumMemoryBytes else {
        throw CodecError(.resourceLimitExceeded, "Compressed input exceeds operation limits.")
    }
}
