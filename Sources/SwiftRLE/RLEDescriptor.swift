// SPDX-License-Identifier: Apache-2.0
// Adapted from raster-labs/DICOMKit @ 4b68d7e22829418c88e48dd53d98b25fee50d90d (Sources/DICOMCore/PixelDataDescriptor.swift, MIT)
import Foundation

/// Explicit RLE dialect selection (API-13).
/// Format auto-detection from raw bytes or file extensions is prohibited.
public enum RLEProfile: String, Sendable, Equatable, CaseIterable {
    /// DICOM PS3.5 Section 8.2.2 and Annex G frame (64-byte header + 1...15 MSB-to-LSB byte-plane segments).
    case dicomRLEFrame = "dicom-rle"
    /// Raw or row-constrained PackBits byte stream (no 64-byte header, no implicit image dimensions).
    case packBits = "packbits"
}

/// Validated external frame descriptor for DICOM RLE frame inspection and decoding (API-13).
/// Because a DICOM RLE 64-byte header records only segment count and byte offsets,
/// frame geometry, sample type, bit depth and colour semantics must be supplied externally.
public struct RLEFrameDescriptor: Sendable, Equatable {
    public let imageDescriptor: ImageDescriptor
    public let planarConfiguration: Int
    public let bytesPerSample: Int
    public let samplesPerPixel: Int
    public let pixelsPerFrame: Int
    public let expectedSegmentCount: Int

    public var width: Int { imageDescriptor.width }
    public var height: Int { imageDescriptor.height }
    public var sampleType: SampleType { imageDescriptor.sampleType }
    public var storageBits: Int { imageDescriptor.storageBits }
    public var meaningfulBits: Int { imageDescriptor.meaningfulBits }
    public var byteOrder: ByteOrder { imageDescriptor.byteOrder }
    public var components: [ComponentRole] { imageDescriptor.components }
    public var colour: ColourInterpretation { imageDescriptor.colour }

    public init(
        imageDescriptor: ImageDescriptor,
        planarConfiguration: Int? = nil,
        limits: ResourceLimits = .default
    ) throws {
        try imageDescriptor.validate(limits: limits)
        guard imageDescriptor.sampleType == .unsignedInteger || imageDescriptor.sampleType == .signedInteger else {
            throw CodecError(.unsupportedFeature, "DICOM RLE frames support integer sample types only.")
        }
        guard imageDescriptor.storageBits == 8 || imageDescriptor.storageBits == 16 else {
            throw CodecError(.unsupportedFeature, "DICOM RLE frames support 8-bit and 16-bit allocated samples only.")
        }
        guard imageDescriptor.alpha == .absent else {
            throw CodecError(.unsupportedFeature, "Alpha channels are not supported in DICOM RLE frames.")
        }

        let bytesPerSample = imageDescriptor.storageBits / 8
        let samplesPerPixel = imageDescriptor.components.count
        let pixelsPerFrame = try checkedMultiply(imageDescriptor.width, imageDescriptor.height)
        let expectedSegments = try checkedMultiply(bytesPerSample, samplesPerPixel)
        guard (1...15).contains(expectedSegments) else {
            throw CodecError(.invalidArgument, "DICOM RLE frame segment count must lie in 1...15.")
        }

        let resolvedPlanar: Int
        if samplesPerPixel == 1 {
            if let explicitPlanar = planarConfiguration, explicitPlanar != 0 {
                throw CodecError(.invalidArgument, "Single-component frames must use planarConfiguration 0.")
            }
            resolvedPlanar = 0
        } else {
            let layoutPlanar: Int
            if imageDescriptor.planes.count == 1 {
                layoutPlanar = 0
            } else if imageDescriptor.planes.count == samplesPerPixel {
                layoutPlanar = 1
            } else {
                throw CodecError(.incompatibleImageLayout, "Multi-component RLE frames require either 1 interleaved plane or 1 plane per component.")
            }
            if let explicitPlanar = planarConfiguration {
                guard explicitPlanar == 0 || explicitPlanar == 1 else {
                    throw CodecError(.invalidArgument, "planarConfiguration must be 0 (interleaved) or 1 (planar).")
                }
                guard explicitPlanar == layoutPlanar else {
                    throw CodecError(.invalidArgument, "planarConfiguration disagrees with ImageDescriptor plane count.")
                }
            }
            resolvedPlanar = layoutPlanar
        }

        self.imageDescriptor = imageDescriptor
        self.planarConfiguration = resolvedPlanar
        self.bytesPerSample = bytesPerSample
        self.samplesPerPixel = samplesPerPixel
        self.pixelsPerFrame = pixelsPerFrame
        self.expectedSegmentCount = expectedSegments
    }

    public init(
        width: Int,
        height: Int,
        sampleType: SampleType = .unsignedInteger,
        storageBits: Int = 16,
        meaningfulBits: Int = 16,
        byteOrder: ByteOrder = .littleEndian,
        components: [ComponentRole] = [.grey],
        colour: ColourInterpretation = .greyscale,
        planarConfiguration: Int = 0,
        rowBytes: Int? = nil,
        offset: Int = 0,
        limits: ResourceLimits = .default
    ) throws {
        guard width > 0, height > 0, offset >= 0, !components.isEmpty else {
            throw CodecError(.invalidArgument, "Frame dimensions and component count must be positive.")
        }
        guard storageBits == 8 || storageBits == 16 else {
            throw CodecError(.unsupportedFeature, "DICOM RLE frames support 8-bit and 16-bit allocated samples only.")
        }
        guard sampleType == .unsignedInteger || sampleType == .signedInteger else {
            throw CodecError(.unsupportedFeature, "DICOM RLE frames support integer sample types only.")
        }
        guard planarConfiguration == 0 || planarConfiguration == 1 else {
            throw CodecError(.invalidArgument, "planarConfiguration must be 0 or 1.")
        }
        if components.count == 1 && planarConfiguration != 0 {
            throw CodecError(.invalidArgument, "Single-component frames must use planarConfiguration 0.")
        }

        let sampleBytes = storageBits / 8
        let planes: [PlaneDescriptor]
        if planarConfiguration == 0 || components.count == 1 {
            let pixelBytes = try checkedMultiply(components.count, sampleBytes)
            let resolvedRowBytes = try rowBytes ?? checkedMultiply(width, pixelBytes)
            let capacity = try checkedAdd(offset, checkedMultiply(resolvedRowBytes, height))
            let plane = try PlaneDescriptor(
                width: width,
                height: height,
                components: Array(0..<components.count),
                offset: offset,
                sampleStride: sampleBytes,
                pixelStride: pixelBytes,
                rowBytes: resolvedRowBytes,
                byteCount: capacity
            )
            planes = [plane]
        } else {
            let resolvedRowBytes = try rowBytes ?? checkedMultiply(width, sampleBytes)
            let planeStride = try checkedMultiply(resolvedRowBytes, height)
            var builtPlanes: [PlaneDescriptor] = []
            builtPlanes.reserveCapacity(components.count)
            for idx in 0..<components.count {
                let planeOffset = try checkedAdd(offset, checkedMultiply(idx, planeStride))
                let planeEnd = try checkedAdd(planeOffset, planeStride)
                let plane = try PlaneDescriptor(
                    width: width,
                    height: height,
                    components: [idx],
                    offset: planeOffset,
                    sampleStride: sampleBytes,
                    pixelStride: sampleBytes,
                    rowBytes: resolvedRowBytes,
                    byteCount: planeEnd
                )
                builtPlanes.append(plane)
            }
            planes = builtPlanes
        }

        let descriptor = try ImageDescriptor(
            width: width,
            height: height,
            sampleType: sampleType,
            storageBits: storageBits,
            meaningfulBits: meaningfulBits,
            byteOrder: byteOrder,
            components: components,
            colour: colour,
            alpha: .absent,
            planes: planes,
            limits: limits
        )
        try self.init(imageDescriptor: descriptor, planarConfiguration: planarConfiguration, limits: limits)
    }

    public static func greyscale16(
        width: Int,
        height: Int,
        meaningfulBits: Int = 16,
        rowBytes: Int? = nil,
        offset: Int = 0,
        limits: ResourceLimits = .default
    ) throws -> Self {
        let descriptor = try ImageDescriptor.greyscale16(
            width: width,
            height: height,
            meaningfulBits: meaningfulBits,
            rowBytes: rowBytes,
            offset: offset,
            limits: limits
        )
        return try Self(imageDescriptor: descriptor, planarConfiguration: 0, limits: limits)
    }
}

/// RLE-specific codec controls (API-04, API-13).
public struct CodecOptions: Sendable, Equatable {
    public let profile: RLEProfile
    public let frameDescriptor: RLEFrameDescriptor?
    /// Bounded packet/control-byte operations permitted per expected output byte (in addition to a 64-operation base allowance).
    public let maximumPacketOperationsPerOutputByte: Int

    public init() {
        self.profile = .dicomRLEFrame
        self.frameDescriptor = nil
        self.maximumPacketOperationsPerOutputByte = 2
    }

    private init(validatedProfile: RLEProfile) {
        self.profile = validatedProfile
        self.frameDescriptor = nil
        self.maximumPacketOperationsPerOutputByte = 2
    }

    public static let dicomRLEFrame = Self(validatedProfile: .dicomRLEFrame)
    public static let packBits = Self(validatedProfile: .packBits)

    public init(
        profile: RLEProfile = .dicomRLEFrame,
        frameDescriptor: RLEFrameDescriptor? = nil,
        maximumPacketOperationsPerOutputByte: Int = 2
    ) throws {
        guard (1...64).contains(maximumPacketOperationsPerOutputByte) else {
            throw CodecError(.invalidArgument, "maximumPacketOperationsPerOutputByte must lie in 1...64.")
        }
        if profile == .packBits && frameDescriptor != nil {
            throw CodecError(.invalidArgument, "PackBits byte profile cannot be combined with a DICOM RLEFrameDescriptor.")
        }
        self.profile = profile
        self.frameDescriptor = frameDescriptor
        self.maximumPacketOperationsPerOutputByte = maximumPacketOperationsPerOutputByte
    }
}
