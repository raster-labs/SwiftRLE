// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftRLE

/// External frame contract, intentionally outside DICOMKit. This is a candidate,
/// not a DICOM parser, transfer syntax registry or downstream cutover.
public struct ExternalFrame: Sendable {
    public let descriptor: RLEFrameDescriptor
    public init(rows:Int,columns:Int,bitsAllocated:Int,bitsStored:Int,signed:Bool,samplesPerPixel:Int,photometric:String,planarConfiguration:Int,rowBytes:Int? = nil) throws {
        let roles:[ComponentRole], colour:ColourInterpretation
        switch photometric {
        case "MONOCHROME1","MONOCHROME2": roles = [.grey]; colour = .greyscale
        case "RGB":roles = [.red,.green,.blue];colour = .rgb
        case "PALETTE COLOR":roles = [.uninterpreted("palette-index")];colour = .unknown
        case "YBR_FULL":roles = [.uninterpreted("Y"),.uninterpreted("Cb"),.uninterpreted("Cr")];colour = .unknown
        default:throw CodecError(.unsupportedFeature,"Unsupported external interpretation")
        }
        guard samplesPerPixel == roles.count else { throw CodecError(.invalidArgument,"Component interpretation mismatch") }
        let base = try RLEFrameDescriptor(width:columns,height:rows,sampleType:signed ? .signedInteger : .unsignedInteger,storageBits:bitsAllocated,meaningfulBits:bitsStored,components:roles,colour:colour,planarConfiguration:planarConfiguration,rowBytes:rowBytes)
        descriptor = try RLEFrameDescriptor(imageDescriptor:base.imageDescriptor,metadata:ImageMetadata(entries:["dicom.photometricInterpretation":Data(photometric.utf8)],requiredKeys:["dicom.photometricInterpretation"]),planarConfiguration:planarConfiguration)
    }
    public func decode(_ frame:Data,into destination:ImageDestination,options:DecodeOptions = .init()) throws -> DecodedImage {
        try Decoder(configuration:.init(codecOptions:CodecOptions(frameDescriptor:descriptor))).decodeSynchronously(frame,into:destination,options:options)
    }
    public func encode(_ image:Image,options:EncodeOptions = .init()) throws -> EncodedImage {
        guard image.descriptor == descriptor.imageDescriptor else { throw CodecError(.incompatibleImageLayout,"External descriptor mismatch") }
        return try Encoder(configuration:EncoderConfiguration(codecOptions:CodecOptions(frameDescriptor:descriptor))).encodeSynchronously(image,options:options)
    }
}
