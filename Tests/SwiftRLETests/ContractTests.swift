// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftRLE

@Suite("Common Contract and Descriptor Validation Tests")
struct ContractTests {

    @Test("CodecError categories match the 10 normative common contract categories")
    func testCodecErrorCategories() {
        let expected: [CodecError.Category] = [
            .invalidArgument, .malformedInput, .unsupportedFormat, .unsupportedFeature,
            .incompatibleImageLayout, .resourceLimitExceeded, .storageUnavailable,
            .backendUnavailable, .ioFailure, .internalFailure
        ]
        #expect(CodecError.Category.allCases == expected)
        let err = CodecError(.invalidArgument, "Test diagnostic.")
        #expect(err.category == .invalidArgument)
        #expect(err.message == "Test diagnostic.")
    }

    @Test("Checked integer arithmetic helpers throw on overflow")
    func testCheckedArithmeticOverflow() throws {
        #expect(try checkedAdd(40, 2) == 42)
        #expect(try checkedMultiply(6, 7) == 42)
        #expect(throws: CodecError.self) {
            _ = try checkedAdd(Int.max, 1)
        }
        #expect(throws: CodecError.self) {
            _ = try checkedMultiply(Int.max, 2)
        }
    }

    @Test("PlaneDescriptor and ImageDescriptor validate geometry, alignment, strides and precision")
    func testDescriptorValidation() throws {
        let d16 = try ImageDescriptor.greyscale16(width: 3, height: 2, meaningfulBits: 12, rowBytes: 8, offset: 4)
        #expect(d16.width == 3)
        #expect(d16.height == 2)
        #expect(d16.storageBits == 16)
        #expect(d16.meaningfulBits == 12)
        #expect(d16.byteOrder == .littleEndian)
        #expect(d16.requiredByteCount == 4 + 8 * 2)

        // Native byteOrder resolves to concrete endianness and .opposite flips it.
        let plane = try PlaneDescriptor(width: 2, height: 2, rowBytes: 4, byteCount: 8)
        let nativeDesc = try ImageDescriptor(width: 2, height: 2, byteOrder: .native, planes: [plane])
        #expect(nativeDesc.byteOrder == .littleEndian || nativeDesc.byteOrder == .bigEndian)
        #expect(nativeDesc.byteOrder.opposite != nativeDesc.byteOrder)

        // Invalid dimensions, offsets, precision, or unaligned strides must throw before touching memory.
        #expect(throws: CodecError.self) {
            _ = try ImageDescriptor.greyscale16(width: 0, height: 2)
        }
        #expect(throws: CodecError.self) {
            _ = try ImageDescriptor.greyscale16(width: 2, height: 2, meaningfulBits: 17)
        }
        #expect(throws: CodecError.self) {
            // Odd rowBytes for 16-bit samples is misaligned.
            _ = try ImageDescriptor.greyscale16(width: 2, height: 2, rowBytes: 5)
        }
        #expect(throws: CodecError.self) {
            // Odd offset for 16-bit samples is misaligned.
            _ = try ImageDescriptor.greyscale16(width: 2, height: 2, rowBytes: 4, offset: 1)
        }
        #expect(throws: CodecError.self) {
            // Subsampled plane rejected with .unsupportedFeature.
            let subPlane = try PlaneDescriptor(width: 1, height: 2, rowBytes: 2, byteCount: 4)
            _ = try ImageDescriptor(width: 2, height: 2, planes: [subPlane])
        }
        #expect(throws: CodecError.self) {
            // Overlapping planes rejected with .incompatibleImageLayout.
            let p0 = try PlaneDescriptor(width: 2, height: 2, components: [0], offset: 0, sampleStride: 1, pixelStride: 1, rowBytes: 2, byteCount: 4)
            let p1 = try PlaneDescriptor(width: 2, height: 2, components: [1], offset: 2, sampleStride: 1, pixelStride: 1, rowBytes: 2, byteCount: 6)
            let p2 = try PlaneDescriptor(width: 2, height: 2, components: [2], offset: 4, sampleStride: 1, pixelStride: 1, rowBytes: 2, byteCount: 8)
            _ = try ImageDescriptor(
                width: 2, height: 2, storageBits: 8, meaningfulBits: 8,
                components: [.red, .green, .blue], colour: .rgb, planes: [p0, p1, p2]
            )
        }
    }

    @Test("ResourceLimits profiles and admission ceiling enforcement")
    func testResourceLimits() throws {
        #expect(ResourceLimits.general.maximumCompressedBytes == 256 * 1024 * 1024)
        #expect(ResourceLimits.watch.maximumCompressedBytes == 16 * 1024 * 1024)
        #expect(ResourceLimits.watch.maximumWorkers == 2)

        #expect(throws: CodecError.self) {
            _ = try ResourceLimits(maximumCompressedBytes: 0)
        }
        #expect(throws: CodecError.self) {
            _ = try ResourceLimits(deadlineSeconds: .nan)
        }

        let smallLimits = try ResourceLimits(
            maximumCompressedBytes: 32,
            maximumDecodedBytes: 16,
            maximumWorkspaceBytes: 16,
            maximumPixels: 8,
            maximumDimension: 4,
            maximumMetadataBytes: 8,
            maximumICCBytes: 4,
            maximumMemoryBytes: 32
        )
        // Dimension limit exceeded
        #expect(throws: CodecError(.resourceLimitExceeded, "Image dimension limit exceeded.")) {
            _ = try ImageDescriptor.greyscale16(width: 5, height: 1, limits: smallLimits)
        }
        // Pixel limit exceeded
        #expect(throws: CodecError(.resourceLimitExceeded, "Image pixel limit exceeded.")) {
            _ = try ImageDescriptor.greyscale16(width: 3, height: 3, limits: smallLimits)
        }
        // Decoded bytes limit exceeded
        #expect(throws: CodecError(.resourceLimitExceeded, "Decoded storage limit exceeded.")) {
            _ = try ImageDescriptor.greyscale16(width: 3, height: 3, limits: try ResourceLimits(maximumDecodedBytes: 10))
        }
    }

    @Test("RLEFrameDescriptor and DecodeOptions.codecOptions resolution and conflict validation")
    func testRLEFrameDescriptorAndOptionReconciliation() throws {
        let frameDescA = try RLEFrameDescriptor.greyscale16(width: 4, height: 3, meaningfulBits: 12, rowBytes: 10)
        #expect(frameDescA.width == 4)
        #expect(frameDescA.height == 3)
        #expect(frameDescA.meaningfulBits == 12)
        #expect(frameDescA.expectedSegmentCount == 2)
        #expect(frameDescA.planarConfiguration == 0)

        let rgbInterleaved = try RLEFrameDescriptor(
            width: 4, height: 2, storageBits: 8, meaningfulBits: 8,
            components: [.red, .green, .blue], colour: .rgb, planarConfiguration: 0
        )
        #expect(rgbInterleaved.expectedSegmentCount == 3)
        #expect(rgbInterleaved.imageDescriptor.planes.count == 1)

        let rgbPlanar16 = try RLEFrameDescriptor(
            width: 4, height: 2, storageBits: 16, meaningfulBits: 16,
            components: [.red, .green, .blue], colour: .rgb, planarConfiguration: 1
        )
        #expect(rgbPlanar16.expectedSegmentCount == 6)
        #expect(rgbPlanar16.imageDescriptor.planes.count == 3)

        // Profile/descriptor conflict: .packBits cannot carry an RLEFrameDescriptor
        #expect(throws: CodecError.self) {
            _ = try CodecOptions(profile: .packBits, frameDescriptor: frameDescA)
        }

        // 1. Configuration-provided descriptor with default DecodeOptions() (codecOptions == nil)
        let configDecoder = try Decoder(
            configuration: DecoderConfiguration(codecOptions: try CodecOptions(frameDescriptor: frameDescA))
        )
        #expect(try configDecoder.resolveFrameDescriptor(for: DecodeOptions()) == frameDescA)

        // 2. Per-call DecodeOptions.codecOptions with default Decoder()
        let defaultDecoder = try Decoder()
        let perCallOptions = DecodeOptions(codecOptions: try CodecOptions(frameDescriptor: frameDescA))
        #expect(try defaultDecoder.resolveFrameDescriptor(for: perCallOptions) == frameDescA)

        // 3. Missing in both configuration and DecodeOptions throws .invalidArgument
        #expect(throws: CodecError.self) {
            _ = try defaultDecoder.resolveFrameDescriptor(for: DecodeOptions())
        }

        // 4. Conflicting descriptors in configuration vs DecodeOptions throws .invalidArgument
        let frameDescB = try RLEFrameDescriptor.greyscale16(width: 2, height: 2, meaningfulBits: 16)
        #expect(throws: CodecError.self) {
            _ = try configDecoder.resolveFrameDescriptor(
                for: DecodeOptions(codecOptions: try CodecOptions(frameDescriptor: frameDescB))
            )
        }

        // 5. Passing .packBits profile to Image-level Encoder or Decoder throws .invalidArgument
        #expect(throws: CodecError.self) {
            _ = try Encoder(configuration: .packBits)
        }
        #expect(throws: CodecError.self) {
            _ = try Decoder(configuration: .packBits)
        }
        #expect(throws: CodecError.self) {
            _ = try configDecoder.resolveFrameDescriptor(for: DecodeOptions(codecOptions: .packBits))
        }

        // 6. Passing .dicomRLEFrame to PackBitsEncoder or PackBitsDecoder throws .invalidArgument
        #expect(throws: CodecError.self) {
            _ = try PackBitsEncoder(configuration: .default)
        }
        #expect(throws: CodecError.self) {
            _ = try PackBitsDecoder(configuration: .default)
        }
    }

    @Test("R2 capabilities and strict DICOM RLE frame validation")
    func testR1CapabilitiesAndDeferredFrameRejection() async throws {
        let encoder = try Encoder()
        let decoder = try Decoder()
        #expect(Encoder.capabilities.canEncode)
        #expect(Decoder.capabilities.canDecode)
        #expect(encoder.capabilities.canEncode)
        #expect(decoder.capabilities.canDecode)
        #expect(decoder.capabilities.canInspect)

        let packEncoder = try PackBitsEncoder()
        let packDecoder = try PackBitsDecoder()
        #expect(packEncoder.capabilities.canEncode)
        #expect(!packEncoder.capabilities.canDecode)
        #expect(packDecoder.capabilities.canDecode)
        #expect(!packDecoder.capabilities.canEncode)

        // EncoderConfiguration rejects lossy and near-lossless modes
        #expect(throws: CodecError.self) {
            _ = try EncoderConfiguration(mode: .lossy)
        }
        #expect(throws: CodecError.self) {
            _ = try EncoderConfiguration(mode: .nearLossless(maximumAbsoluteError: 0))
        }
        #expect(throws: CodecError.self) {
            _ = try EncoderConfiguration(mode: .nearLossless(maximumAbsoluteError: 2))
        }

        // Image-level encode/inspect/decode reject deferred R2 DICOM frame profile with .unsupportedFeature
        let desc = try ImageDescriptor.greyscale16(width: 2, height: 2, meaningfulBits: 12)
        let dest = try ImageDestination.allocate(descriptor: desc)
        let image = try dest.writeUInt16 { x, y in UInt16(x + y * 2) }
        let frameDesc = try RLEFrameDescriptor(imageDescriptor: desc)
        let decOpts = DecodeOptions(codecOptions: try CodecOptions(frameDescriptor: frameDesc))

        let encoded = try await encoder.encode(image)
        let info = try decoder.inspect(encoded.data, options: decOpts)
        #expect(info.descriptor == desc)
        let decoded = try await decoder.decode(encoded.data, options: decOpts)
        #expect(try decoded.image.sampleUInt16(x: 1, y: 1) == 3)
        #expect(throws: CodecError.self) { _ = try decoder.inspect(Data(repeating: 0, count: 64), options: decOpts) }

    }
}
