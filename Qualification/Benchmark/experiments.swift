// SPDX-License-Identifier: Apache-2.0
// Unshipped qualification experiments: bounded SIMD packet scanning and frame scheduling.
import Foundation
import CandidateRLE
import CryptoKit
import BenchSystem
import Synchronization
import Dispatch

func seconds(_ d:Duration)->Double {Double(d.components.seconds)+Double(d.components.attoseconds)/1e18}
func emit(_ o:[String:Any])throws {print(String(data:try JSONSerialization.data(withJSONObject:o,options:[.sortedKeys]),encoding:.utf8)!);fflush(stdout)}
@inline(never) func scalar(_ p:UnsafeRawBufferPointer,_ offset:Int,_ limit:Int)->Int {
 let byte=p[offset];var n=1;while n<limit && p[offset+n]==byte{n+=1};return n
}
@inline(never) func vector(_ p:UnsafeRawBufferPointer,_ offset:Int,_ limit:Int)->Int {
 let byte=p[offset];var n=1
 while n+16<=limit {
  let v=p.loadUnaligned(fromByteOffset:offset+n,as:SIMD16<UInt8>.self)
  if v != SIMD16<UInt8>(repeating:byte){break};n+=16
 }
 while n<limit && p[offset+n]==byte{n+=1};return n
}
let args=CommandLine.arguments
if args.contains("--validate-frames") {
 for width in [512,2048] {try await validateFrames(width)}
 exit(0)
}
if args.count==5 && args[1]=="--frame-memory" {
 let width=Int(args[2])!,op=args[3],workers=Int(args[4])!
 guard [512,2048].contains(width),["encode","decode"].contains(op),[1,2].contains(workers) else{exit(2)}
 let f=try FrameWork(width),setup=bench_memory()
 let counts=try await CandidateRLE.BenchmarkTelemetry.measureAsync {_ = try await batch(f,op,workers)}
 let m=bench_memory()
 try emit(["experiment":"isolated bounded frames memory","width":width,"operation":op,"workers":workers,"frames":4,"setupPeakRSSBytes":setup.peak_rss_bytes,"peakRSSBytes":m.peak_rss_bytes,"owned":counts,"maximumAdmittedBytes":f.aggregateBound(op,workers),"retainedSharedInputPixelBytes":f.image.storage.byteCount,"retainedCompressedReferenceBytes":f.encoded.count,"workspaceBoundBytesPerWorker":0,"ownedCounterScope":"in-scope decoder-owned outputs only; retained source pixels excluded; encode compressed Data separately bounded","shipped":false]);exit(0)
}
let clock=ContinuousClock()
var differentialChecks=0
for length in [1,2,3,7,15,16,17,31,32,33,63,64,65,127,128,129] {
 for offset in [0,1,3] {for split in 0...length {
 var data=Data(repeating:37,count:offset+length);if split<length {data[offset+split]=99}
 data.withUnsafeBytes{p in let a=scalar(p,offset,length),b=vector(p,offset,length);precondition(a==b);differentialChecks+=1}
 }}
}
for length in [7,17,64,128] {for pattern in ["flat","early-break","tail-break"] {
 var data=Data(repeating:37,count:length+3);if pattern=="early-break"{data[4]=99};if pattern=="tail-break"{data[length+2]=99}
 var a:[Double]=[],b:[Double]=[];var check=0
 for iteration in 0..<25 {for which in (iteration%2==0 ? [0,1]:[1,0]) {
 let start=clock.now;let result=data.withUnsafeBytes {p in var count=0;for _ in 0..<100000 {count += which==0 ? scalar(p,3,length):vector(p,3,length)};return count};let elapsed=seconds(clock.now-start);check ^= result
 if iteration>=5 {if which==0{a.append(elapsed)}else{b.append(elapsed)}}
 }}
 try emit(["experiment":"SIMD16 bounded repeat scan","length":length,"pattern":pattern,"scalar":a,"candidate":b,"callsPerSample":100000,"warmups":5,"iterations":20,"differentialChecks":differentialChecks,"checksum":check,"shipped":false])
}}

struct FrameWork:Sendable {
 let image:CandidateRLE.Image;let encoded:Data;let options:CandidateRLE.DecodeOptions;let encoder:CandidateRLE.Encoder;let decoder:CandidateRLE.Decoder
 init(_ width:Int)throws {
 let frame=try CandidateRLE.RLEFrameDescriptor(width:width,height:width,storageBits:16,meaningfulBits:16,rowBytes:width*2+14)
 image=try CandidateRLE.ImageDestination.allocate(descriptor:frame.imageDescriptor).writeUInt16{x,y in UInt16(truncatingIfNeeded:x*17+y*91)}
 encoder=try CandidateRLE.Encoder();decoder=try CandidateRLE.Decoder();encoded=try encoder.encodeSynchronously(image).data;options=CandidateRLE.DecodeOptions(codecOptions:try CandidateRLE.CodecOptions(frameDescriptor:frame))
 }
 func aggregateBound(_ op:String,_ workers:Int)->Int {
  let width=image.descriptor.width,height=image.descriptor.height
  let encodedOutputBound=64+2*((width+(width+2)/3)*height+1)
  // Scalar frame path has no row/plane workspace allocation. Include retained
  // shared pixels/reference plus each worker's final image or worst-case Data.
  return image.storage.byteCount+encoded.count+workers*(op=="encode" ? encodedOutputBound:image.storage.byteCount)
 }
 @concurrent func execute(_ op:String)async throws->Int {
 if op=="encode" {let r=try await encoder.encode(image);guard r.data==encoded else{throw NSError(domain:"ConcurrentBytes",code:1)};return r.data.count}
 let r=try await decoder.decode(encoded,options:options);guard try r.image.sampleUInt16(x:1,y:1)==108 else{throw NSError(domain:"ConcurrentSamples",code:1)};return r.image.storage.byteCount
 }
}
func batch(_ f:FrameWork,_ op:String,_ workers:Int)async throws->Int {
 // Caller supplies one immutable shared source; at most workers results/scratch exist.
 // Aggregate admitted capacity uses input + compressed input + per-worker final output.
 let aggregate=f.aggregateBound(op,workers)
 guard aggregate<256*1024*1024 && (1...2).contains(workers) else{throw NSError(domain:"AggregateAdmission",code:1)}
 return try await withThrowingTaskGroup(of:Int.self) {group in
 var next=0,total=0
 for _ in 0..<workers {group.addTask{try await f.execute(op)};next+=1}
 while let n=try await group.next() {total ^= n;if next<4 {group.addTask{try Task.checkCancellation();return try await f.execute(op)};next+=1}}
 return total
 }
}
for width in [512,2048] {
 let f=try FrameWork(width)
 for op in ["encode","decode"] {
 var samples:[[Double]]=[[],[]];var checksum=0
 for iteration in 0..<25 {for workers in (iteration%2==0 ? [1,2]:[2,1]) {
 let start=clock.now;let result=try await batch(f,op,workers);let elapsed=seconds(clock.now-start);checksum ^= result;if iteration>=5{samples[workers-1].append(elapsed)}
 }}
 let counts=try await CandidateRLE.BenchmarkTelemetry.measureAsync {_ = try await batch(f,op,2)}
 let cancel=Task {try Task.checkCancellation();return try await batch(f,op,2)};cancel.cancel();var cancellationObserved=false
 do {_ = try await cancel.value}catch is CancellationError {cancellationObserved=true}
 precondition(cancellationObserved)
 let memory=bench_memory()
 try emit(["experiment":"bounded independent frames","width":width,"height":width,"framesPerBatch":4,"operation":op,"serial":samples[0],"workers2":samples[1],"warmups":5,"iterations":20,"maximumInFlight":2,"aggregateAdmissionBytes":f.aggregateBound(op,2),"retainedSharedInputPixelBytes":f.image.storage.byteCount,"retainedCompressedReferenceBytes":f.encoded.count,"workspaceBoundBytesPerWorker":0,"ownedCounterScope":"in-scope decoder-owned outputs only; retained source pixels excluded; encode compressed Data separately bounded","ordinaryOwnedCounters":counts,"cancellationObserved":cancellationObserved,"processPeakRSSBytes":memory.peak_rss_bytes,"memoryLimit":"process peak cumulative across experiments, advisory; isolated frame memory measured by Bench separately","checksum":checksum,"shipped":false])
 }
}
try emit(["experiment":"optional GPU decision","gpuExecuted":false,"decision":"defer","reason":"Variable-length PackBits state and bounded CPU packet scans; this milestone measures scalar/SIMD/frame scheduling first. No Metal backend or UMA sharing claim. GPU dispatch/transfer/compile benchmark remains unexecuted; no GPU performance conclusion asserted."])

func validateFrames(_ width:Int) async throws {
 let f=try FrameWork(width)
 let expected=try f.image.storage.withUnsafeBytes{Data($0)}
 let validated=try await withThrowingTaskGroup(of:Int.self) {group in
  var next=0,count=0
  for _ in 0..<2 {group.addTask {
   let r=try await f.decoder.decode(f.encoded,options:f.options)
   let actual=try r.image.storage.withUnsafeBytes{Data($0)}
   guard actual==expected else{throw NSError(domain:"FullSamplesAndPadding",code:1)}
   return actual.count
  };next+=1}
  while let n=try await group.next(){count+=n;if next<4 {group.addTask {
   let r=try await f.decoder.decode(f.encoded,options:f.options)
   let actual=try r.image.storage.withUnsafeBytes{Data($0)}
   guard actual==expected else{throw NSError(domain:"FullSamplesAndPadding",code:2)}
   return actual.count
  };next+=1}}
  return count
 }
 precondition(validated==4*expected.count)
 // Deterministic test barrier: both active operations have reconstructed/sealed
 // pixels but remain inside the completed callback, before successful return.
 let completed=Mutex(0),cancelled=Mutex(0),release=DispatchSemaphore(value:0)
 let counts=try await CandidateRLE.BenchmarkTelemetry.measureAsync {
  let task=Task {
   try await withThrowingTaskGroup(of:Bool.self) {group in
    for _ in 0..<2 {group.addTask {
     let options=CandidateRLE.DecodeOptions(codecOptions:f.options.codecOptions,progress:{update in
      if case .completed=update.phase {completed.withLock{$0+=1};precondition(release.wait(timeout:.now()+5) == .success)}
     })
     do {_ = try await f.decoder.decode(f.encoded,options:options);return false}
     catch is CancellationError{return true}
    }}
    for try await value in group {if value{cancelled.withLock{$0+=1}}else{throw NSError(domain:"PublishedAfterActiveCancellation",code:1)}}
   }
  }
  let deadline=ContinuousClock.now.advanced(by:.seconds(5))
  while completed.withLock({$0})<2 && ContinuousClock.now<deadline {try await Task.sleep(for:.milliseconds(1))}
  let both=completed.withLock{$0}==2
  task.cancel();release.signal();release.signal();try await task.value
  precondition(both && cancelled.withLock{$0}==2)
 }
 precondition(counts["pixelAllocations"]==2 && counts["pixelReleases"]==2 && counts["copyBytes"]==0)
 try emit(["experiment":"untimed full-frame and active cancellation validation","width":width,"validatedFrames":4,"logicalSamplesCompared":4*width*width,"storageBytesIncludingPaddingCompared":validated,"maximumInFlight":2,"activeWorkersReachedCompletedCallback":completed.withLock{$0},"cancelledBeforeSuccessfulReturn":cancelled.withLock{$0},"joinedWorkers":2,"ordinaryOwnedCounters":counts,"validationCopies":"Data copies only in untimed equality helper; not codec handoff/timing/accounting","cancellationBoundary":"both active decodes reconstructed/sealed owners, before return; no claim of cancellation mid-packet","shipped":false])
}
