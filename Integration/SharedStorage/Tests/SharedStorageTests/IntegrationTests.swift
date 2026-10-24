// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SharedStorage
import DICOMKitCandidate
@testable import SwiftRLE
import SwiftJLS

private func expected(_ x:Int,_ y:Int,_ bits:Int)->UInt16 {
    let values:[UInt16] = bits == 12 ? [0,4095,257,2048,19,3001,4094] : [0,65535,257,32768,19,60001,65534]
    return values[(x+3*y)%values.count]
}
private func rleFixture(bits:Int,padding:UInt8 = 0xA5) throws -> (Data,SwiftRLE.RLEFrameDescriptor) {
    let frame = try SwiftRLE.RLEFrameDescriptor.greyscale16(width:7,height:3,meaningfulBits:bits,rowBytes:20)
    let destination = try SwiftRLE.ImageDestination.allocate(descriptor:frame.imageDescriptor)
    let image = try destination.write { bytes in
        bytes.initializeMemory(as:UInt8.self,repeating:padding)
        for y in 0..<3 { for x in 0..<7 { let v=expected(x,y,bits);bytes[y*20+x*2]=UInt8(truncatingIfNeeded:v);bytes[y*20+x*2+1]=UInt8(v>>8) } }
    }
    return (try SwiftRLE.Encoder().encodeSynchronously(image).data,frame)
}
private func assertSamples(_ image:SwiftRLE.Image,_ bits:Int)throws { for y in 0..<3 { for x in 0..<7 { #expect(try image.sampleUInt16(x:x,y:y) == expected(x,y,bits)) } } }

@Test func realBidirectionalSharedStorageAndAllocatorTelemetry() async throws {
    for bits in [12,16] {
        let (source,_) = try rleFixture(bits:bits)
        #expect(try rleFixture(bits:bits,padding:0x3C).0 == source)
        for big in [false,true] {
            let recorder = SwiftRLE.StorageTelemetry.Recorder()
            let forward = try await SwiftRLE.StorageTelemetry.$recorder.withValue(recorder) {
                try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:bits,rowBytes:24,bigEndian:big)
            }
            #expect(recorder.counts.pixelAllocations == 1)
            #expect(recorder.counts.pixelReleases == 1)
            #expect(recorder.counts.copyBytes == 0)
            #expect(forward.writes == 1 && forward.reads > 0)
            let jdecoded = try await SwiftJLS.Decoder().decode(forward.data)
            #expect(jdecoded.image.descriptor.meaningfulBits == bits)
            for y in 0..<3 { for x in 0..<7 { #expect(try jdecoded.image.sampleUInt16(x:x,y:y) == expected(x,y,bits)) } }
            recorder.reset()
            let backward = try await SwiftRLE.StorageTelemetry.$recorder.withValue(recorder) {
                try await Transcoder.run(forward.data,direction:.jlsToRLE,width:7,height:3,bits:bits,rowBytes:28,bigEndian:big)
            }
            #expect(recorder.counts.pixelAllocations == 1 && recorder.counts.pixelReleases == 1)
            #expect(recorder.counts.copyBytes == 0 && backward.writes == 1 && backward.reads > 0)
            let descriptor = try SwiftRLE.RLEFrameDescriptor.greyscale16(width:7,height:3,meaningfulBits:bits,rowBytes:18)
            let decoded = try SwiftRLE.Decoder(configuration:.init(codecOptions:SwiftRLE.CodecOptions(frameDescriptor:descriptor))).decodeSynchronously(backward.data)
            try assertSamples(decoded.image,bits)
            // Retain compressed endpoints for independent DCMTK oracle qualification.
            if let directory = ProcessInfo.processInfo.environment["SWIFTRLE_SHARED_ORACLE_OUTPUT"],!big {
                let root=URL(fileURLWithPath:directory);try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
                try forward.data.write(to:root.appendingPathComponent("rle-to-jls-\(bits).jls"))
                try backward.data.write(to:root.appendingPathComponent("jls-to-rle-\(bits).rle"))
            }
        }
    }
}

@Test func ownerLifecyclePreflightAndConcurrentReaders() async throws {
    let owner = try SharedOwner(byteCount:80), rle = RLEView(owner), jls = JLSView(owner)
    #expect(throws:(any Error).self) { try jls.withUnsafeBytes { _ in } }
    #expect(throws:(any Error).self) { try jls.withUnsafeMutableBytes(lease:SwiftJLS.StorageWriteLease()) { _ in } }
    let lease = try jls.reserveWrite()
    #expect(throws:(any Error).self) { try rle.reserveWrite() }
    try jls.withUnsafeMutableBytes(lease:lease) { bytes in
        #expect(throws:(any Error).self) { try rle.withUnsafeMutableBytes(lease:SwiftRLE.StorageWriteLease()) { _ in } }
        bytes.initializeMemory(as:UInt8.self,repeating:0)
    }
    _ = try jls.finishAndSeal(lease:lease)
    #expect(throws:(any Error).self) { try jls.reserveWrite() }
    #expect(throws:(any Error).self) { try jls.withUnsafeMutableBytes(lease:lease) { _ in } }
    async let a = Task.detached { try jls.withUnsafeBytes { $0.reduce(0){$0+Int($1)} } }.value
    async let b = Task.detached { try rle.withUnsafeBytes { $0.reduce(0){$0+Int($1)} } }.value
    #expect(try await a == b)
    let(source,_) = try rleFixture(bits:12)
    do { _ = try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:12,rowBytes:10);Issue.record("invalid stride accepted") } catch {}
    do { _ = try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:12,rowBytes:20,budget:100);Issue.record("aggregate limit accepted") } catch {}
    // Cancel inside the operation's task, before entering the real transcoder.
    // Caller-side cancel() races with completion of this tiny fixture.
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(Task.isCancelled)
        return try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:12,rowBytes:20)
    }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
}

@Test func candidatePreservesExternalMonochromeAndCallerOwner() throws {
    for bits in [12,16] {
        let(source,frame) = try rleFixture(bits:bits)
        let external = try ExternalFrame(rows:3,columns:7,bitsAllocated:16,bitsStored:bits,signed:false,samplesPerPixel:1,photometric:"MONOCHROME1",planarConfiguration:0,rowBytes:20)
        let owner = try SwiftRLE.OwnedImageStorage(byteCount:frame.imageDescriptor.requiredByteCount)
        let destination = try SwiftRLE.ImageDestination(descriptor:frame.imageDescriptor,storage:owner)
        let decoded = try external.decode(source,into:destination)
        #expect(decoded.image.storage.allocationID == owner.allocationID)
        #expect(decoded.image.metadata.entries["dicom.photometricInterpretation"] == Data("MONOCHROME1".utf8))
        try assertSamples(decoded.image,bits)
        #expect(try external.encode(decoded.image).data == source)
    }
}

@Test func actualCodecsPreflightReuseAndBeganWriteInvalidation() async throws {
    let(source,frame) = try rleFixture(bits:16)
    let owner = try SharedOwner(byteCount:frame.imageDescriptor.requiredByteCount), view = RLEView(owner)
    let destination = try SwiftRLE.ImageDestination(descriptor:frame.imageDescriptor,storage:view)
    let decoder = try SwiftRLE.Decoder(configuration:.init(codecOptions:SwiftRLE.CodecOptions(frameDescriptor:frame)))
    do { _ = try await decoder.decode(Data(),into:destination);Issue.record("empty accepted") } catch {}
    let good = try await decoder.decode(source,into:destination)
    #expect(good.image.storage.allocationID == owner.storage.allocationID)
    let jview = JLSView(owner), jdesc = try SwiftJLS.ImageDescriptor.greyscale16(width:7,height:3,rowBytes:20)
    let image = try SwiftJLS.Image(descriptor:jdesc,storage:jview)
    async let a = SwiftJLS.Encoder().encode(image)
    async let b = SwiftJLS.Encoder().encode(image)
    let(first,second) = try await(a,b)
    #expect(first.data == second.data)
    #expect(throws:(any Error).self) { try view.reserveWrite() }
    let invalidOwner = try SharedOwner(byteCount:frame.imageDescriptor.requiredByteCount), invalidView=RLEView(invalidOwner)
    let invalidDestination = try SwiftRLE.ImageDestination(descriptor:frame.imageDescriptor,storage:invalidView)
    var damaged=source; damaged.removeLast(2)
    do { _ = try await decoder.decode(damaged,into:invalidDestination);Issue.record("truncated accepted") } catch {}
    // Header-boundary failures may occur before writing; exercise an explicit
    // begun-write callback failure through the shared provider as well.
    let begunOwner=try SharedOwner(byteCount:80),begun=JLSView(begunOwner)
    let token=try begun.reserveWrite()
    try begun.withUnsafeMutableBytes(lease:token) { $0[0]=31 }
    try begun.abortAndInvalidate(lease:token)
    #expect(throws:(any Error).self) { try begun.reserveWrite() }
    #expect(throws:(any Error).self) { try begun.withUnsafeBytes{_ in} }
}

@Test func realBackendFallbackLimitsAndCancellation() async throws {
    let(source,frame) = try rleFixture(bits:12)
    let owner=try SharedOwner(byteCount:frame.imageDescriptor.requiredByteCount),view=RLEView(owner)
    let destination=try SwiftRLE.ImageDestination(descriptor:frame.imageDescriptor,storage:view)
    let decoder=try SwiftRLE.Decoder(configuration:.init(codecOptions:SwiftRLE.CodecOptions(frameDescriptor:frame)))
    do { _=try await decoder.decode(source,into:destination,options:.init(executionPolicy:.required(.accelerated)));Issue.record("required backend accepted") } catch {}
    let decoded=try await decoder.decode(source,into:destination,options:.init(executionPolicy:.preferred(.accelerated)))
    #expect(decoded.report.fallbackReason != nil)
    let jdesc=try SwiftJLS.ImageDescriptor.greyscale16(width:7,height:3,meaningfulBits:12,rowBytes:20)
    let image=try SwiftJLS.Image(descriptor:jdesc,storage:JLSView(owner))
    do { _=try await SwiftJLS.Encoder().encode(image,options:.init(executionPolicy:.required(.accelerated)));Issue.record("peer required backend accepted") } catch {}
    let fallback=try await SwiftJLS.Encoder().encode(image,options:.init(executionPolicy:.preferred(.accelerated)))
    #expect(fallback.report.fallbackReason != nil)
    let low=try SwiftJLS.ResourceLimits(maximumMemoryBytes:32)
    do { _=try await SwiftJLS.Encoder().encode(image,options:.init(resourceLimits:low));Issue.record("peer limits accepted") } catch {}
    // Establish cancellation before the actual peer encode without throwing in
    // the test first; the peer operation must itself return CancellationError.
    let task=Task {
        withUnsafeCurrentTask { $0?.cancel() }
        #expect(Task.isCancelled)
        return try await SwiftJLS.Encoder().encode(image)
    }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
}

@Test func realStrideEndianMutationControls() async throws {
    let(source,_) = try rleFixture(bits:16)
    let baseline=try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:16,rowBytes:24)
    for mutation in [SwiftRLE.SharedPathMutation.ignoreRowStride,.wrongByteOrder] {
        let changed=try await SwiftRLE.SharedPathMutation.$active.withValue(mutation) {
            try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:16,rowBytes:24)
        }
        #expect(changed.data != baseline.data)
        let decoded=try await SwiftJLS.Decoder().decode(changed.data)
        var mismatches=0
        for y in 0..<3 { for x in 0..<7 { if try decoded.image.sampleUInt16(x:x,y:y) != expected(x,y,16) { mismatches += 1 } } }
        #expect(mismatches > 0)
        print("mutation \(mutation): \(mismatches) independently expected sample mismatches")
    }
    #expect(try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:16,rowBytes:24).data == baseline.data)
}

@Test func independentlyEncodedJPEG_LSInput() async throws {
    guard let directory=ProcessInfo.processInfo.environment["SWIFTRLE_SHARED_ORACLE_OUTPUT"] else { throw SwiftRLE.CodecError(.ioFailure,"Independent oracle fixture directory required") }
    let root=URL(fileURLWithPath:directory)
    for bits in [12,16] {
        let source=try Data(contentsOf:root.appendingPathComponent("independent-\(bits).jls"))
        let result=try await Transcoder.run(source,direction:.jlsToRLE,width:7,height:3,bits:bits,rowBytes:26,bigEndian:true)
        let descriptor=try SwiftRLE.RLEFrameDescriptor.greyscale16(width:7,height:3,meaningfulBits:bits,rowBytes:22)
        let decoded=try SwiftRLE.Decoder(configuration:.init(codecOptions:SwiftRLE.CodecOptions(frameDescriptor:descriptor))).decodeSynchronously(result.data)
        try assertSamples(decoded.image,bits)
        try result.data.write(to:root.appendingPathComponent("oracle-jls-to-rle-\(bits).rle"))
    }
}

@Test func preflightRefusalsAllocateNoPixels() async throws {
    for direction in [Transcoder.Direction.rleToJLS,.jlsToRLE] {
        let recorder=SwiftRLE.StorageTelemetry.Recorder()
        do {
            _=try await SwiftRLE.StorageTelemetry.$recorder.withValue(recorder) { try await Transcoder.run(Data([0,1,2]),direction:direction,width:7,height:3,bits:16,rowBytes:20) }
            Issue.record("Malformed source accepted")
        } catch {}
        #expect(recorder.counts.pixelAllocations == 0)
    }
    let(source,_) = try rleFixture(bits:16)
    let decoded=try SwiftRLE.Decoder(configuration:.init(codecOptions:SwiftRLE.CodecOptions(frameDescriptor:SwiftRLE.RLEFrameDescriptor.greyscale16(width:7,height:3,rowBytes:20)))).decodeSynchronously(source)
    let owner=try SharedOwner(byteCount:60),view=RLEView(owner),destination=try SwiftRLE.ImageDestination(descriptor:decoded.image.descriptor,storage:view)
    _=try destination.write { bytes in try decoded.image.storage.withUnsafeBytes { bytes.copyMemory(from:$0) } }
    let jdesc=try SwiftJLS.ImageDescriptor.greyscale16(width:7,height:3,rowBytes:20),image=try SwiftJLS.Image(descriptor:jdesc,storage:JLSView(owner))
    let near=try await SwiftJLS.Encoder(configuration:.init(mode:.nearLossless(maximumAbsoluteError:2))).encode(image)
    let recorder=SwiftRLE.StorageTelemetry.Recorder()
    do { _=try await SwiftRLE.StorageTelemetry.$recorder.withValue(recorder) { try await Transcoder.run(near.data,direction:.jlsToRLE,width:7,height:3,bits:16,rowBytes:20) };Issue.record("Near-lossless history accepted") } catch {}
    #expect(recorder.counts.pixelAllocations == 0)
}

private final class CancelAfterBorrow: SwiftJLS.WritableImageStorage, Sendable {
    let view:JLSView
    init(_ owner:SharedOwner) { view=JLSView(owner) }
    var byteCount:Int { view.byteCount };var allocationID:UUID { view.allocationID }
    func reserveWrite()throws->SwiftJLS.StorageWriteLease { try view.reserveWrite() }
    func withUnsafeMutableBytes<R>(lease:SwiftJLS.StorageWriteLease,_ body:(UnsafeMutableRawBufferPointer)throws->R)throws->R {
        let result=try view.withUnsafeMutableBytes(lease:lease,body)
        withUnsafeCurrentTask { $0?.cancel() };return result
    }
    func finishAndSeal(lease:SwiftJLS.StorageWriteLease)throws->any SwiftJLS.ReadOnlyImageStorage { try view.finishAndSeal(lease:lease) }
    func abortAndInvalidate(lease:SwiftJLS.StorageWriteLease)throws { try view.abortAndInvalidate(lease:lease) }
}
@Test func cancellationAfterActualPeerWriteInvalidatesOwner() async throws {
    let(source,_) = try rleFixture(bits:16)
    let jls=try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:16,rowBytes:20)
    let owner=try SharedOwner(byteCount:60),provider=CancelAfterBorrow(owner),descriptor=try SwiftJLS.ImageDescriptor.greyscale16(width:7,height:3,rowBytes:20)
    let task=Task { try await SwiftJLS.Decoder().decode(jls.data,into:SwiftJLS.ImageDestination(descriptor:descriptor,storage:provider)) }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(owner.observed.writes == 1)
    #expect(throws:(any Error).self) { try RLEView(owner).reserveWrite() }
    #expect(throws:(any Error).self) { try JLSView(owner).withUnsafeBytes { _ in } }
}

@Test func exactAggregateBoundary() async throws {
    let(source,_) = try rleFixture(bits:16)
    let baseline=try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:16,rowBytes:24)
    #expect(try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:16,rowBytes:24,budget:baseline.admittedBytes).data == baseline.data)
    do { _=try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:16,rowBytes:24,budget:baseline.admittedBytes-1);Issue.record("Below aggregate boundary admitted") } catch {}
}

#if SWIFTRLE_PEER_ALLOCATION_AUDIT
import Synchronization
@Test func instrumentedActualPeerAllocator() async throws {
    let count=Mutex(0)
    try SwiftJLS.PixelAllocationProbe.$observer.withValue({ _ in count.withLock{$0 += 1} }) {
        _=try SwiftJLS.OwnedImageStorage(byteCount:64)
    }
    #expect(count.withLock{$0} == 1) // positive control proves constructor hook runs
    count.withLock{$0=0}
    let(source,_) = try rleFixture(bits:16)
    try await SwiftJLS.PixelAllocationProbe.$observer.withValue({ _ in count.withLock{$0 += 1} }) {
        let forward=try await Transcoder.run(source,direction:.rleToJLS,width:7,height:3,bits:16,rowBytes:24)
        _=try await Transcoder.run(forward.data,direction:.jlsToRLE,width:7,height:3,bits:16,rowBytes:28)
    }
    #expect(count.withLock{$0} == 0)
    print("ordinary-build peer actual pixel allocator: positive control1, real two-way transcode0")
}
#endif

@Test func candidateBaselineInterpretationAndLayoutMatrix() throws {
    for photo in ["MONOCHROME1","MONOCHROME2","RGB","YBR_FULL","PALETTE COLOR"] {
        let count=["RGB","YBR_FULL"].contains(photo) ? 3 : 1
        for allocated in [8,16] {
            for planar in (count == 3 ? [0,1] : [0]) {
                for signed in (photo.hasPrefix("MONO") ? [false,true] : [false]) {
                    let bits=allocated == 16 ? 12 : 8
                    let row=5*(planar == 0 ? count : 1)*(allocated/8)+4
                    let contract=try ExternalFrame(rows:3,columns:5,bitsAllocated:allocated,bitsStored:bits,signed:signed,samplesPerPixel:count,photometric:photo,planarConfiguration:planar,rowBytes:row)
                    let descriptor=contract.descriptor.imageDescriptor
                    let source=try SwiftRLE.ImageDestination.allocate(descriptor:descriptor).write { bytes in
                        bytes.initializeMemory(as:UInt8.self,repeating:0xA5)
                        for plane in descriptor.planes { for y in 0..<3 { for x in 0..<5 { for (local,component) in plane.components.enumerated() {
                            let pattern=(x+3*y+component)%3
                            let value:UInt16=pattern == 0 ? 0 : pattern == 1 ? UInt16((1 << (bits-(signed ? 1 : 0)))-1) : signed ? (allocated == 8 ? 255 : 65535) : 1
                            let offset=plane.offset+y*plane.rowBytes+x*plane.pixelStride+local*plane.sampleStride
                            bytes[offset]=UInt8(truncatingIfNeeded:value);if allocated == 16 { bytes[offset+1]=UInt8(value>>8) }
                        } } } }
                    }
                    let encoded=try contract.encode(source)
                    let owner=try SwiftRLE.OwnedImageStorage(byteCount:descriptor.requiredByteCount),destination=try SwiftRLE.ImageDestination(descriptor:descriptor,storage:owner)
                    let decoded=try contract.decode(encoded.data,into:destination)
                    #expect(decoded.image.storage.allocationID == owner.allocationID)
                    #expect(decoded.image.metadata.entries["dicom.photometricInterpretation"] == Data(photo.utf8))
                    try source.storage.withUnsafeBytes { expected in try decoded.image.storage.withUnsafeBytes { actual in
                        for plane in descriptor.planes { for y in 0..<3 { for x in 0..<5 { for local in plane.components.indices {
                            let offset=plane.offset+y*plane.rowBytes+x*plane.pixelStride+local*plane.sampleStride
                            for lane in 0..<allocated/8 { #expect(actual[offset+lane] == expected[offset+lane]) }
                        } } } }
                    } }
                }
            }
        }
    }
    #expect(throws:(any Error).self) { try ExternalFrame(rows:3,columns:5,bitsAllocated:16,bitsStored:12,signed:false,samplesPerPixel:3,photometric:"YBR_FULL_422",planarConfiguration:0) }
}

@Test func nontrivialAggregateBoundaryBothDirections() async throws {
    let width=513,height=512,frame=try SwiftRLE.RLEFrameDescriptor.greyscale16(width:width,height:height,rowBytes:1032)
    let image=try SwiftRLE.ImageDestination.allocate(descriptor:frame.imageDescriptor).writeUInt16 { x,y in UInt16(truncatingIfNeeded:(x*193+y*31337)^0xA53C) }
    let source=try await SwiftRLE.Encoder().encode(image)
    let forward=try await Transcoder.run(source.data,direction:.rleToJLS,width:width,height:height,bits:16,rowBytes:1036,budget:64*1024*1024)
    #expect(try await Transcoder.run(source.data,direction:.rleToJLS,width:width,height:height,bits:16,rowBytes:1036,budget:forward.admittedBytes).data == forward.data)
    let backward=try await Transcoder.run(forward.data,direction:.jlsToRLE,width:width,height:height,bits:16,rowBytes:1040,budget:64*1024*1024)
    #expect(try await Transcoder.run(forward.data,direction:.jlsToRLE,width:width,height:height,bits:16,rowBytes:1040,budget:backward.admittedBytes).data == backward.data)
    for (input,direction,admission,row) in [(source.data,Transcoder.Direction.rleToJLS,forward.admittedBytes,1036),(forward.data,.jlsToRLE,backward.admittedBytes,1040)] {
        do { _=try await Transcoder.run(input,direction:direction,width:width,height:height,bits:16,rowBytes:row,budget:admission-1);Issue.record("Large below-boundary admitted") } catch {}
    }
}

@Test func nativeReportsNormalizeTwelveBitSourceAndCountOwnerOnce() async throws {
    // Independently authored DICOM RLE: two 3-sample rows, literal packets per
    // row/segment, with deliberately noncanonical high allocated bits.
    var source = Data(repeating:0,count:64)
    for (word,value) in [(0,2),(1,64),(2,72)] {
        for lane in 0..<4 { source[word*4+lane] = UInt8(truncatingIfNeeded:value >> (lane*8)) }
    }
    source.append(contentsOf:[2,0xF0,0xFA,0xF1,2,0xFF,0xF0,0xF7])
    source.append(contentsOf:[2,0x01,0xBC,0x23,2,0xFF,0x00,0x00])
    let expected:[UInt16] = [1,0xABC,0x123,0xFFF,0,0x700]
    let recorder=SwiftRLE.StorageTelemetry.Recorder()
    let forward=try await SwiftRLE.StorageTelemetry.$recorder.withValue(recorder) {
        try await Transcoder.run(source,direction:.rleToJLS,width:3,height:2,bits:12,rowBytes:10)
    }
    #expect(recorder.counts.pixelAllocations == 1 && recorder.counts.pixelBytes == 20)
    #expect(forward.report.rle.sampleNormalizations == ["Unused allocated bits masked/sign-extended in final output."])
    #expect(forward.report.stages.map(\.codec) == [.rle,.jpegLS])
    #expect(forward.report.stages.map(\.operation) == [.decode,.encode])
    #expect(forward.report.normalizationStages.count == 1)
    #expect(forward.report.normalizationStages.first?.sampleNormalizations == forward.report.rle.sampleNormalizations)
    #expect(forward.report.stages.last?.sampleNormalizations == nil)
    #expect(forward.report.fidelity == .exactSamples)
    #expect(forward.report.stages.allSatisfy { $0.backend == .scalarCPU && $0.fidelity == .exactSamples })
    #expect(forward.report.sharedPixelAllocationCount == 1 && forward.report.sharedPixelCapacity == 20)
    #expect(forward.report.codecPixelAllocationCount == 0 && forward.report.totalPixelAllocationCount == 1)
    #expect(forward.report.measuredPeakPixelBytes == 20)
    #expect(forward.report.copyEvents.isEmpty && forward.report.fallbackStages.isEmpty)
    #expect(forward.report.rle.peakWorkspaceBytes == 0)
    #expect(forward.report.jpegLS.peakWorkspaceBytes == nil && forward.report.measuredPeakWorkspaceBytes == nil)
    #expect(forward.report.admittedRLEWorkspaceBytes == 64 && forward.report.admittedJPEG_LSWorkspaceBytes > 65536)
    #expect(forward.report.admittedWorkspaceBytes == forward.report.admittedRLEWorkspaceBytes + forward.report.admittedJPEG_LSWorkspaceBytes)
    let decoded=try await SwiftJLS.Decoder().decode(forward.data)
    for y in 0..<2 { for x in 0..<3 { #expect(try decoded.image.sampleUInt16(x:x,y:y) == expected[y*3+x]) } }
    recorder.reset()
    let reverse=try await SwiftRLE.StorageTelemetry.$recorder.withValue(recorder) {
        try await Transcoder.run(forward.data,direction:.jlsToRLE,width:3,height:2,bits:12,rowBytes:12,bigEndian:true)
    }
    #expect(recorder.counts.pixelAllocations == 1 && recorder.counts.pixelBytes == 24)
    #expect(reverse.report.stages.map(\.codec) == [.jpegLS,.rle])
    #expect(reverse.report.stages.map(\.operation) == [.decode,.encode])
    #expect(reverse.report.rle.sampleNormalizations.isEmpty && reverse.report.normalizationStages.isEmpty)
    #expect(reverse.report.sharedPixelCapacity == 24 && reverse.report.sharedPixelAllocationCount == 1)
    #expect(reverse.report.codecPixelAllocationCount == 0 && reverse.report.totalPixelAllocationCount == 1)
    #expect(reverse.report.measuredPeakPixelBytes == 24 && reverse.report.measuredPeakWorkspaceBytes == nil)
    #expect(reverse.report.fidelity == .exactSamples && reverse.report.copyEvents.isEmpty)
    let frame=try SwiftRLE.RLEFrameDescriptor.greyscale16(width:3,height:2,meaningfulBits:12,rowBytes:8)
    let rdecoded=try SwiftRLE.Decoder(configuration:.init(codecOptions:SwiftRLE.CodecOptions(frameDescriptor:frame))).decodeSynchronously(reverse.data)
    for y in 0..<2 { for x in 0..<3 { #expect(try rdecoded.image.sampleUInt16(x:x,y:y) == expected[y*3+x]) } }
}

@Test func reportMappingRetainsNonemptyFactsAndUnknownMeasurements() throws {
    // Report-mapping unit test only: these values are explicit synthetic facts,
    // not a claim that this profile executes an accelerated/lossy transcode.
    let rle=SwiftRLE.OperationReport(backend:.scalarCPU,fallbackReason:"RLE fallback",fidelity:.boundedError(2),copyEvents:[try SwiftRLE.CopyEvent(reason:"rle conversion",bytesMoved:7,sourceLayout:"A",destinationLayout:"B")],pixelAllocationCount:nil,peakPixelBytes:nil,peakWorkspaceBytes:11,elapsedSeconds:0.5,sampleNormalizations:["normalization fact"])
    let jls=SwiftJLS.OperationReport(backend:.accelerated,fallbackReason:"peer fallback",fidelity:.lossy,copyEvents:[try SwiftJLS.CopyEvent(reason:"peer conversion",bytesMoved:11,sourceLayout:"B",destinationLayout:"C")],pixelAllocationCount:0,peakPixelBytes:0,peakWorkspaceBytes:nil,elapsedSeconds:0.75)
    for direction in [Transcoder.Direction.rleToJLS,.jlsToRLE] {
        let report=Transcoder.Report(rle:rle,jpegLS:jls,direction:direction,capacity:512,rleBound:32,jlsBound:64)
        #expect(report.rle == rle && report.jpegLS == jls)
        #expect(report.copyEvents.count == 2 && report.copyEvents.reduce(0) { $0+$1.event.bytesMoved } == 18)
        #expect(Set(report.copyEvents.map(\.event.reason)) == Set(["rle conversion","peer conversion"]))
        #expect(report.fallbackStages.count == 2 && report.normalizationStages.count == 1)
        #expect(report.sharedPixelAllocationCount == 1 && report.sharedPixelCapacity == 512)
        #expect(report.codecPixelAllocationCount == nil && report.totalPixelAllocationCount == nil)
        #expect(report.measuredPeakWorkspaceBytes == nil && report.measuredPeakPixelBytes == nil)
        #expect(report.admittedWorkspaceBytes == 96 && report.fidelity == nil)
        #expect(report.stages.first?.operation == .decode && report.stages.last?.operation == .encode)
    }
}
