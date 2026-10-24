// SPDX-License-Identifier: Apache-2.0
// Benchmark-only minimal contexts, not a DICOMKit production adapter.
import Foundation
public protocol ImageCodec {} 
public protocol ImageEncoder {}
public struct TransferSyntax:Sendable { public static let rleLossless=TransferSyntax();public var uid:String { "1.2.840.10008.1.2.5" } }
public enum DICOMError:Error { case parsingFailed(String),limitExceeded(String) }
public struct CompressionConfiguration { public init(){} }
public struct PixelDataDescriptor {
 public let columns:Int,rows:Int,bitsAllocated:Int,samplesPerPixel:Int,planarConfiguration:Int
 public init(columns:Int,rows:Int,bitsAllocated:Int,samplesPerPixel:Int=1,planarConfiguration:Int=0) { self.columns=columns;self.rows=rows;self.bitsAllocated=bitsAllocated;self.samplesPerPixel=samplesPerPixel;self.planarConfiguration=planarConfiguration }
 public var bytesPerSample:Int{bitsAllocated/8};public var pixelsPerFrame:Int{columns*rows};public var bytesPerFrame:Int{pixelsPerFrame*bytesPerSample*samplesPerPixel}
}
extension Data { func readUInt32LE(at i:Int)->UInt32? { guard i>=0,i+4<=count else{return nil};let p=startIndex+i;return UInt32(self[p])|UInt32(self[p+1])<<8|UInt32(self[p+2])<<16|UInt32(self[p+3])<<24 } }
