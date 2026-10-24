// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftRLE

@Suite("R4 validated scalar addressing")
struct OptimizationTests {
    @Test func referenceDifferentialAcrossLayoutsAndPacketTails() throws {
        for width in [1,2,3,7,127,128,129] {
            for bits in [1,7,8,12,16] {
                for signed in [false,true] {
                    for big in [false,true] {
                        let storage=bits<=8 ? 8:16
                        let frame=try RLEFrameDescriptor(width:width,height:3,sampleType:signed ? .signedInteger:.unsignedInteger,
                            storageBits:storage,meaningfulBits:bits,byteOrder:big ? .bigEndian:.littleEndian,rowBytes:width*(storage/8)+8,offset:2)
                        let mask=(UInt32(1)<<bits)-1
                        let image=try FrameTests.source(frame) { _,x,y in
                            var v=UInt32((x*71+y*389)&65535)&mask
                            if signed && v & (UInt32(1)<<(bits-1)) != 0 {v |= (storage==8 ? 255:65535)^mask}
                            return UInt16(v)
                        }
                        try compare(image,frame)
                    }
                }
            }
        }
        for planar in [0,1] { for big in [false,true] { for storage in [8,16] {
            let frame=try RLEFrameDescriptor(width:17,height:3,storageBits:storage,meaningfulBits:storage,
                byteOrder:big ? .bigEndian:.littleEndian,components:[.red,.green,.blue],colour:.rgb,planarConfiguration:planar,
                rowBytes:17*(storage/8)*(planar==0 ? 3:1)+8,offset:2)
            let image=try FrameTests.source(frame) { c,x,y in UInt16((c*91+x*17+y*13)&(storage==8 ? 255:65535)) }
            try compare(image,frame)
        }}}
    }
    @Test func singlePixelHasIndependentPacketAndLaneValues() throws {
        for storage in [8,16] { for colour in [false,true] { for planar in (colour ? [0,1]:[0]) { for big in [false,true] {
            let components:[ComponentRole] = colour ? [.red,.green,.blue]:[.grey]
            let frame=try RLEFrameDescriptor(width:1,height:1,storageBits:storage,meaningfulBits:storage,
                byteOrder:big ? .bigEndian:.littleEndian,components:components,colour:colour ? .rgb:.greyscale,
                planarConfiguration:planar,rowBytes:(storage/8)*(planar==0 ? components.count:1)+8,offset:2)
            let image=try FrameTests.source(frame){component,_,_ in UInt16((component*53+173)&(storage==8 ? 255:65535))}
            var expected=Data(repeating:0,count:64)
            func word(_ n:Int,_ slot:Int) {for b in 0..<4 {expected[slot*4+b]=UInt8(truncatingIfNeeded:n>>(8*b))}}
            word(frame.expectedSegmentCount,0)
            for segment in 0..<frame.expectedSegmentCount {
                word(64+2*segment,segment+1)
                let component=segment/(storage/8),lane=segment%(storage/8)
                let sample=UInt16((component*53+173)&(storage==8 ? 255:65535))
                expected.append(0) // independently known one-byte literal packet
                expected.append(UInt8(truncatingIfNeeded:sample>>(8*((storage/8)-1-lane))))
            }
            let encoder=try Encoder()
            for policy in [ExecutionPolicy.automatic,.scalarCPU,.required(.scalarCPU)] {
                #expect(try encoder.encodeSynchronously(image,options:EncodeOptions(executionPolicy:policy)).data==expected)
            }
            try compare(image,frame)
        }}}}
    }
    @Test func singletonDoesNotEagerlyMultiplyUnusedHugeStrides() throws {
        let plane=try PlaneDescriptor(width:1,height:1,sampleStride:Int.max,pixelStride:Int.max,rowBytes:Int.max,byteCount:1)
        let descriptor=try ImageDescriptor(width:1,height:1,storageBits:8,meaningfulBits:8,planes:[plane])
        let frame=try RLEFrameDescriptor(imageDescriptor:descriptor)
        let image=try ImageDestination.allocate(descriptor:descriptor).write{$0[0]=173}
        try compare(image,frame)
    }
    private func compare(_ image:Image,_ frame:RLEFrameDescriptor) throws {
        let encoder=try Encoder(),decoder=try Decoder()
        let reference=try encoder.encodeSynchronously(image,options:EncodeOptions(executionPolicy:.scalarCPU))
        let candidate=try encoder.encodeSynchronously(image)
        #expect(reference.data==candidate.data)
        let codec=try CodecOptions(frameDescriptor:frame)
        let referenceOptions=DecodeOptions(executionPolicy:.scalarCPU,codecOptions:codec)
        let candidateOptions=DecodeOptions(codecOptions:codec)
        let a=try decoder.decodeSynchronously(reference.data,options:referenceOptions)
        let recorder=StorageTelemetry.Recorder()
        let b=try StorageTelemetry.$recorder.withValue(recorder) {try decoder.decodeSynchronously(candidate.data,options:candidateOptions)}
        let aa=try a.image.storage.withUnsafeBytes{Data($0)},bb=try b.image.storage.withUnsafeBytes{Data($0)}
        #expect(aa==bb)
        #expect(recorder.counts.pixelAllocations==1)
        #expect(recorder.counts.workspaceAllocations==0)
        #expect(recorder.counts.copyBytes==0)
        let rawA=try DICOMRLEFrame.decodeAllocatedCells(reference.data,descriptor:frame,options:referenceOptions)
        let rawB=try DICOMRLEFrame.decodeAllocatedCells(candidate.data,descriptor:frame,options:candidateOptions)
        #expect(try rawA.storage.withUnsafeBytes{Data($0)} == rawB.storage.withUnsafeBytes{Data($0)})
        let destination=try ImageDestination.allocate(descriptor:frame.imageDescriptor)
        let c=try decoder.decodeSynchronously(candidate.data,into:destination,options:candidateOptions)
        #expect(c.image.storage.allocationID==destination.storage.allocationID)
        #expect(try c.image.storage.withUnsafeBytes{Data($0)}==bb)
        #expect(candidate.report.backend == .scalarCPU)
        #expect(b.report.backend == .scalarCPU)
    }
}
