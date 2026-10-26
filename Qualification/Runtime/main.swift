// SPDX-License-Identifier: Apache-2.0
// Synthetic coordinate fixtures, independently authored packet vectors; CC0.
// Executed in the target process, not a host surrogate. No private datasets.
import Foundation
import SwiftRLE

struct Failure: Error { let message: String }
func require(_ condition: Bool, _ message: String) throws {
    if !condition { throw Failure(message: message) }
}
func rejects(_ category: CodecError.Category? = nil, _ body: () throws -> Void) throws {
    do { try body() } catch let e as CodecError {
        try require(category == nil || category == e.category, "wrong rejection category")
        return
    }
    throw Failure(message: "operation did not reject")
}
func fixture(_ segments: [[UInt8]]) -> Data {
    var b = [UInt8](repeating: 0,count: 64)
    func word(_ v: Int,_ slot: Int) { for j in 0..<4 { b[slot*4+j] = UInt8(truncatingIfNeeded: v >> (8*j)) } }
    word(segments.count,0)
    for (i,s) in segments.enumerated() { word(b.count,i+1); b += s }
    return Data(b)
}
func cell(_ b: UnsafeRawBufferPointer,_ d: ImageDescriptor,_ c: Int,_ x: Int,_ y: Int) throws -> UInt16 {
    guard let p = d.planes.first(where: {$0.components.contains(c)}), let ci = p.components.firstIndex(of: c) else { throw Failure(message: "missing plane") }
    let at = p.offset+y*p.rowBytes+x*p.pixelStride+ci*p.sampleStride
    if d.storageBits == 8 { return UInt16(b[at]) }
    let lo = d.byteOrder == .littleEndian ? b[at] : b[at+1]
    let hi = d.byteOrder == .littleEndian ? b[at+1] : b[at]
    return UInt16(lo) | UInt16(hi)<<8
}
func source(_ frame: RLEFrameDescriptor,_ pad: UInt8 = 0xA7,_ value: (Int,Int,Int)->UInt16) throws -> Image {
    let d = frame.imageDescriptor
    return try ImageDestination.allocate(descriptor:d,limits:.watch).write { b in
        b.initializeMemory(as:UInt8.self,repeating:pad)
        for p in d.planes { for y in 0..<d.height { for x in 0..<d.width { for (ci,c) in p.components.enumerated() {
            let at=p.offset+y*p.rowBytes+x*p.pixelStride+ci*p.sampleStride, v=value(c,x,y)
            if d.storageBits == 8 { b[at]=UInt8(truncatingIfNeeded:v) }
            else { b[at]=UInt8(truncatingIfNeeded:d.byteOrder == .littleEndian ? v : v>>8); b[at+1]=UInt8(truncatingIfNeeded:d.byteOrder == .littleEndian ? v>>8 : v) }
        } } } }
    }
}
// Cancels after actual final-buffer fill, before seal/publication. The provider
// retains its owner and forwards its authoritative exclusive lease unchanged.
final class CancellingStorage: WritableImageStorage, Sendable {
    let owner: OwnedImageStorage
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    init(_ count: Int) throws { owner = try OwnedImageStorage(byteCount: count,limits:.watch) }
    func reserveWrite() throws -> StorageWriteLease { try owner.reserveWrite() }
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,_ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R {
        try owner.withUnsafeMutableBytes(lease:lease) { bytes in
            let result = try body(bytes)
            withUnsafeCurrentTask { $0?.cancel() }
            return result
        }
    }
    func finishAndSeal(lease: StorageWriteLease) throws -> any ReadOnlyImageStorage { try owner.finishAndSeal(lease:lease) }
    func abortAndInvalidate(lease: StorageWriteLease) throws { try owner.abortAndInvalidate(lease:lease) }
}
@main struct RuntimeQualification {
    static func main() async throws {
        let decoder=try Decoder(), encoder=try Encoder()
        let pack=try PackBitsDecoder()
        for (coded,expected):([UInt8],[UInt8]) in [([2,65,66,67],[65,66,67]),([255,127],[127,127]),([129,0],Array(repeating:0,count:128)),([128,0,42],[42])] {
            try require(try pack.decode(Data(coded),expectedByteCount:expected.count).data == Data(expected),"known packet")
        }
        let row=Data((0..<258).map { UInt8(truncatingIfNeeded:$0) })
        let packed=try PackBitsEncoder().encode(row,rowBytes:129,rowCount:2)
        try require(try pack.decodeIncremental([packed.data.prefix(3),packed.data.dropFirst(3)],expectedByteCount:258,rowBytes:129,rowCount:2).data == row,"row tail/incremental")
        try rejects { _ = try pack.decode(Data([2,1]),expectedByteCount:3) }
        let profiles:[([ComponentRole],ColourInterpretation,SampleType)]=[
            ([.grey],.greyscale,.unsignedInteger),([.grey],.greyscale,.signedInteger),
            ([.red,.green,.blue],.rgb,.unsignedInteger),
            ([.uninterpreted("palette-index")],.unknown,.unsignedInteger),
            ([.uninterpreted("Y"),.uninterpreted("Cb"),.uninterpreted("Cr")],.unknown,.unsignedInteger)]
        var cases=0
        for (roles,colour,type) in profiles { for bits in [8,16] { for precision in bits == 8 ? [8] : [12,16] { for planar in roles.count == 1 ? [0] : [0,1] { for order:ByteOrder in [.littleEndian,.bigEndian] {
            let rowBytes=(5*(planar == 0 ? roles.count:1)+4)*(bits/8)
            let f=try RLEFrameDescriptor(width:5,height:3,sampleType:type,storageBits:bits,meaningfulBits:precision,byteOrder:order,components:roles,colour:colour,planarConfiguration:planar,rowBytes:rowBytes,offset:4,limits:.watch)
            func value(_ c:Int,_ x:Int,_ y:Int)->UInt16 {
                let mask=(1<<precision)-1, low=[0,mask,1,1<<(precision-1),mask-1,83][(x+y*5+c)%6]&mask
                return UInt16(type == .signedInteger && low&(1<<(precision-1)) != 0 ? low|((bits == 8 ? 255:65535)^mask):low)
            }
            let image=try source(f,0xA7,value), other=try source(f,0x3B,value)
            let encoded=try await encoder.encode(image,options:EncodeOptions(resourceLimits:.watch))
            try require(try encoder.encodeSynchronously(other,options:EncodeOptions(resourceLimits:.watch)).data == encoded.data,"padding reached stream")
            let scalar=try encoder.encodeSynchronously(image,options:EncodeOptions(resourceLimits:.watch,executionPolicy:.scalarCPU))
            try require(scalar.data == encoded.data,"scalar bytes differ")
            let opts=DecodeOptions(resourceLimits:.watch,codecOptions:try CodecOptions(frameDescriptor:f))
            _ = try decoder.inspect(encoded.data,options:opts)
            let allocated=try await decoder.decode(encoded.data,options:opts)
            let out=try RLEFrameDescriptor(width:5,height:3,sampleType:type,storageBits:bits,meaningfulBits:precision,byteOrder:order == .littleEndian ? .bigEndian:.littleEndian,components:roles,colour:colour,planarConfiguration:roles.count == 1 ? 0:1-planar,rowBytes:rowBytes+32,offset:8,limits:.watch)
            let destination=try ImageDestination.allocate(descriptor:out.imageDescriptor,limits:.watch), id=destination.storage.allocationID
            let direct=try await decoder.decode(encoded.data,into:destination,options:opts)
            try require(direct.image.storage.allocationID == id && direct.report.pixelAllocationCount == 0 && direct.report.copyEvents.isEmpty && allocated.report.pixelAllocationCount == 1,"ownership/report")
            for result in [allocated,direct] {
                try result.image.storage.withUnsafeBytes { b in
                    for y in 0..<3 { for x in 0..<5 { for c in roles.indices { try require(try cell(b,result.image.descriptor,c,x,y) == value(c,x,y),"sample mismatch") } } }
                }
            }
            try rejects(.storageUnavailable) { _ = try destination.storage.reserveWrite() }
            cases += 1
        } } } } }
        // Noncanonical source cells must normalize only on Image route; raw route retains cells.
        for signed in [false,true] {
            let f=try RLEFrameDescriptor(width:3,height:1,sampleType:signed ? .signedInteger:.unsignedInteger,storageBits:16,meaningfulBits:12)
            let bytes=fixture([[2,0xA0,0xA8,0xAF],[2,1,0,255]])
            let opts=DecodeOptions(resourceLimits:.watch,codecOptions:try CodecOptions(frameDescriptor:f))
            let normal=try await decoder.decode(bytes,options:opts), raw=try DICOMRLEFrame.decodeAllocatedCells(bytes,descriptor:f,options:DecodeOptions(resourceLimits:.watch))
            let expected:[UInt16]=signed ? [1,0xF800,0xFFFF]:[1,0x800,0xFFF]
            try normal.image.storage.withUnsafeBytes { b in for x in 0..<3 { try require(try cell(b,f.imageDescriptor,0,x,0)==expected[x],"canonical interpretation") } }
            try raw.storage.withUnsafeBytes { b in for (x,v) in [UInt16(0xA001),0xA800,0xAFFF].enumerated() { try require(try cell(b,f.imageDescriptor,0,x,0)==v,"raw cells") } }
        }
        let f=try RLEFrameDescriptor.greyscale16(width:5,height:3,meaningfulBits:12,rowBytes:12)
        let image=try source(f) { _,x,y in UInt16(x+y*5) }
        let bytes=try encoder.encodeSynchronously(image).data
        let options=DecodeOptions(resourceLimits:.watch,codecOptions:try CodecOptions(frameDescriptor:f))
        for n in 0..<bytes.count { try rejects { _ = try decoder.decodeSynchronously(bytes.prefix(n),options:options) } }
        for limits in [try ResourceLimits(maximumCompressedBytes:bytes.count-1),try ResourceLimits(maximumDecodedBytes:1),try ResourceLimits(maximumPixels:1),try ResourceLimits(maximumMemoryBytes:bytes.count+1)] {
            try rejects(.resourceLimitExceeded) { _ = try decoder.decodeSynchronously(bytes,options:DecodeOptions(resourceLimits:limits,codecOptions:try CodecOptions(frameDescriptor:f))) }
        }
        let reusable=try ImageDestination.allocate(descriptor:f.imageDescriptor,limits:.watch)
        try rejects { _ = try decoder.decodeSynchronously(Data(repeating:0,count:64),into:reusable,options:options) }
        _ = try reusable.writeUInt16 { _,_ in 0 }
        // Cancel an active operation from its reconstruction progress callback.
        let task=Task {
            try await encoder.encode(image,options:EncodeOptions(resourceLimits:.watch,progress:{ update in
                if update.phase == .processing { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        do { _ = try await task.value; throw Failure(message:"active cancellation published") } catch is CancellationError { }
        let provider=try CancellingStorage(f.imageDescriptor.requiredByteCount)
        let interrupted=try ImageDestination(descriptor:f.imageDescriptor,storage:provider,limits:.watch)
        let decodeTask=Task { try await decoder.decode(bytes,into:interrupted,options:options) }
        do { _ = try await decodeTask.value; throw Failure(message:"cancelled filled decode published") } catch is CancellationError { }
        try rejects(.storageUnavailable) { _ = try provider.reserveWrite() }
        let deadline=try ResourceLimits(deadlineSeconds:0.001)
        try rejects(.resourceLimitExceeded) {
            _ = try decoder.decodeSynchronously(bytes,options:DecodeOptions(resourceLimits:deadline,codecOptions:try CodecOptions(frameDescriptor:f),progress:{ update in
                if update.phase == .inspecting { Thread.sleep(forTimeInterval:0.01) }
            }))
        }
        try await withThrowingTaskGroup(of:Data.self) { group in
            for _ in 0..<2 { group.addTask { try await encoder.encode(image,options:EncodeOptions(resourceLimits:.watch)).data } }
            for try await actual in group { try require(actual == bytes,"concurrent retained reader") }
        }
        let output:[String:Any] = ["status":"passed","profileCases":cases,"packBitsKnownVectors":4,"canonicalRawCases":2,"truncations":bytes.count,"resourceRejections":4,"activeCancellation":"encoder processing callback; decoder provider cancels after final-buffer fill before seal","deadline":true,"ownership":true,"profile":"ResourceLimits.watch (all fixture allocations <32MiB, max2 concurrent readers)","compiledPlatform":{
            #if os(iOS)
            return "iOS"
            #elseif os(tvOS)
            return "tvOS"
            #elseif os(watchOS)
            return "watchOS"
            #elseif os(visionOS)
            return "xrOS"
            #else
            return "macOS"
            #endif
        }(),"compiledSimulator":{
            #if targetEnvironment(simulator)
            return true
            #else
            return false
            #endif
        }(),"processOS":ProcessInfo.processInfo.operatingSystemVersionString,"processEnvironment":ProcessInfo.processInfo.environment.filter { ["SIMULATOR_ARCHS","SIMULATOR_DEVICE_NAME","SIMULATOR_MODEL_IDENTIFIER","SIMULATOR_RUNTIME_BUILD_VERSION","SIMULATOR_RUNTIME_VERSION","SIMULATOR_UDID"].contains($0.key) }]
        print(String(decoding:try JSONSerialization.data(withJSONObject:output,options:[.sortedKeys]),as:UTF8.self))
    }
}
