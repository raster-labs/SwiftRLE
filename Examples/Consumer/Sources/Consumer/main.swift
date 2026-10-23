// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftRLE

@main
struct Consumer {
    static func main() async throws {
        // 1. Exercise common ImageDescriptor, ImageDestination, OwnedImageStorage & 12-in-16 sample access
        let descriptor = try SwiftRLE.ImageDescriptor.greyscale16(
            width: 3,
            height: 2,
            meaningfulBits: 12,
            rowBytes: 8
        )
        let reusableDestination = try SwiftRLE.ImageDestination.allocate(descriptor: descriptor)
        let allocationID = reusableDestination.storage.allocationID

        let encoder = try SwiftRLE.Encoder()
        let decoder = try SwiftRLE.Decoder()
        guard !encoder.capabilities.canEncode, !decoder.capabilities.canDecode, !decoder.capabilities.canInspect else {
            throw SwiftRLE.CodecError(.internalFailure, "Milestone R1 must not claim DICOM RLE frame capabilities before R2.")
        }

        // 2. Verify both configuration-level and per-call DecodeOptions.codecOptions call shapes compile
        //    and that preflight rejection leaves reusableDestination intact.
        let frameDescriptor = try SwiftRLE.RLEFrameDescriptor(imageDescriptor: descriptor)
        let configuredDecoder = try SwiftRLE.Decoder(
            configuration: SwiftRLE.DecoderConfiguration(
                codecOptions: try SwiftRLE.CodecOptions(frameDescriptor: frameDescriptor)
            )
        )
        do {
            _ = try configuredDecoder.inspect(Data(repeating: 0, count: 64))
            throw SwiftRLE.CodecError(.internalFailure, "Expected R1 DICOM frame inspect preflight rejection.")
        } catch let error as SwiftRLE.CodecError where error.category == .unsupportedFeature {
            // Expected in R1
        }

        do {
            _ = try await decoder.decode(
                Data(repeating: 0, count: 64),
                into: reusableDestination,
                options: SwiftRLE.DecodeOptions(
                    codecOptions: try SwiftRLE.CodecOptions(frameDescriptor: frameDescriptor)
                )
            )
            throw SwiftRLE.CodecError(.internalFailure, "Expected R1 DICOM frame decode preflight rejection.")
        } catch let error as SwiftRLE.CodecError where error.category == .unsupportedFeature {
            // Expected in R1; reusableDestination must remain writable.
        }

        let image = try reusableDestination.writeUInt16 { x, y in
            UInt16(x == 0 ? 4095 : y * 3 + x)
        }
        guard image.storage.allocationID == allocationID,
              try image.sampleUInt16(x: 0, y: 1) == 4095,
              try image.sampleUInt16(x: 2, y: 1) == 5 else {
            throw SwiftRLE.CodecError(.internalFailure, "Owned storage sample preservation failed.")
        }

        // 3. Exercise standalone scalar PackBitsEncoder and PackBitsDecoder (byte-stream, row-constrained & incremental)
        let packEncoder = try SwiftRLE.PackBitsEncoder()
        let packDecoder = try SwiftRLE.PackBitsDecoder()
        guard packEncoder.capabilities.canEncode, packDecoder.capabilities.canDecode else {
            throw SwiftRLE.CodecError(.internalFailure, "PackBits byte engine capabilities must be advertised in R1.")
        }

        let rowPayload = Data([
            0xAA, 0xAA, 0xAA, 0x10, 0x20, 0x30, 0x7F, 0x7F,
            0x7F, 0x7F, 0x41, 0x42, 0x43, 0x00, 0x00, 0x00
        ])
        let encoded = try packEncoder.encode(rowPayload, rowBytes: 8, rowCount: 2)
        let decoded = try packDecoder.decode(
            encoded.data,
            expectedByteCount: rowPayload.count,
            rowBytes: 8,
            rowCount: 2
        )
        let incrementalDecoded = try packDecoder.decodeIncremental(
            [encoded.data.prefix(4), encoded.data.dropFirst(4)],
            expectedByteCount: rowPayload.count,
            rowBytes: 8,
            rowCount: 2
        )
        guard decoded.data == rowPayload,
              incrementalDecoded.data == rowPayload,
              decoded.consumedByteCount == encoded.data.count,
              encoded.report.pixelAllocationCount == 0,
              decoded.report.pixelAllocationCount == 0,
              encoded.report.peakWorkspaceBytes == 0,
              decoded.report.peakWorkspaceBytes == 0 else {
            throw SwiftRLE.CodecError(.internalFailure, "PackBits byte engine round-trip or report check failed.")
        }

        print("Independent SwiftRLE consumer passed: owning storage preserved 12-bit samples and PackBits encoded \(rowPayload.count) bytes into \(encoded.data.count) bytes.")
    }
}
