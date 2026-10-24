// SPDX-License-Identifier: Apache-2.0
import Foundation
import BaselineRLE
import CandidateRLE
import CryptoKit
import Predecessor
import BenchSystem

struct Case: Codable {
 let width:Int; let height:Int; let bits:Int; let pattern:String; let padded:Bool; let big:Bool
 let components:Int; let planar:Int; let colour:String
 var sampleBytes:Int { bits<=8 ? 1:2 }
 var logicalBytes:Int { width*height*sampleBytes*components }
 var rowBytes:Int { width*sampleBytes*(planar==0 ? components:1)+(padded ? 14:0) }
 var offset:Int { padded ? 2:0 }
 var identifier:String { "\(width)x\(height)-\(bits)-\(pattern)-\(colour)-p\(planar)-\(padded ? "padded":"packed")-\(big ? "BE":"LE")" }
}
func digest(_ d:Data)->String { SHA256.hash(data:d).map{String(format:"%02x",$0)}.joined() }
func seconds(_ d:Duration)->Double { Double(d.components.seconds)+Double(d.components.attoseconds)/1e18 }
func value(_ c:Case,_ component:Int,_ x:Int,_ y:Int)->UInt16 {
 let mask=c.bits<=8 ? 255:(c.bits==12 ? 4095:65535)
 return UInt16((c.pattern=="flat" ? 37+component*13 : (c.pattern=="ramp" ? x+y*7+component*91 : ((x &* 1664525) ^ (y &* 1013904223) ^ ((x*y) &* 69069) ^ (component &* 224682251)))) & mask)
}
func packed(_ c:Case)->Data {
 var data=Data(count:c.logicalBytes)
 data.withUnsafeMutableBytes { (p:UnsafeMutableRawBufferPointer) in
 for component in 0..<c.components {for y in 0..<c.height {for x in 0..<c.width {
 let i=(c.planar==0 ? (y*c.width+x)*c.components+component : component*c.width*c.height+y*c.width+x)*c.sampleBytes
 let v=value(c,component,x,y);p[i]=UInt8(truncatingIfNeeded:c.big && c.sampleBytes==2 ? v>>8:v)
 if c.sampleBytes==2 {p[i+1]=UInt8(truncatingIfNeeded:c.big ? v:v>>8)}
 }}}
 };return data
}
// Typed operations keep output owners alive past the timer. No hashing, dictionaries,
// report inspection, sample traversal or output conversion occurs in timed calls.
struct Scalar {
 let image:BaselineRLE.Image;let encoded:Data;let encoder:BaselineRLE.Encoder;let decoder:BaselineRLE.Decoder;let options:BaselineRLE.DecodeOptions
 init(_ c:Case)throws {
 let roles:[BaselineRLE.ComponentRole]=c.components==1 ? [.grey]:(c.colour=="rgb" ? [.red,.green,.blue]:[.uninterpreted("Y"),.uninterpreted("Cb"),.uninterpreted("Cr")])
 let frame=try BaselineRLE.RLEFrameDescriptor(width:c.width,height:c.height,storageBits:c.sampleBytes*8,meaningfulBits:c.bits,byteOrder:c.big ? .bigEndian:.littleEndian,components:roles,colour:c.components==1 ? .greyscale:(c.colour=="rgb" ? .rgb:.unknown),planarConfiguration:c.planar,rowBytes:c.rowBytes,offset:c.offset)
 image=try BaselineRLE.ImageDestination.allocate(descriptor:frame.imageDescriptor).write { out in
 out.initializeMemory(as:UInt8.self,repeating:0xA5)
 for (pi,plane) in frame.imageDescriptor.planes.enumerated() { _=pi;for (ci,component) in plane.components.enumerated(){for y in 0..<c.height{for x in 0..<c.width{
 let i=plane.offset+y*plane.rowBytes+x*plane.pixelStride+ci*plane.sampleStride;let v=value(c,component,x,y)
 out[i]=UInt8(truncatingIfNeeded:c.big && c.sampleBytes==2 ? v>>8:v);if c.sampleBytes==2{out[i+1]=UInt8(truncatingIfNeeded:c.big ? v:v>>8)}
 }}}}
 }
 encoder=try BaselineRLE.Encoder();decoder=try BaselineRLE.Decoder();options=BaselineRLE.DecodeOptions(codecOptions:try BaselineRLE.CodecOptions(frameDescriptor:frame));encoded=try encoder.encodeSynchronously(image).data
 }
 func encode()throws->BaselineRLE.EncodedImage {try encoder.encodeSynchronously(image)}
 func decode()throws->BaselineRLE.DecodedImage {try decoder.decodeSynchronously(encoded,options:options)}
}
struct Candidate {
 let image:CandidateRLE.Image;let encoded:Data;let encoder:CandidateRLE.Encoder;let decoder:CandidateRLE.Decoder;let options:CandidateRLE.DecodeOptions
 init(_ c:Case)throws {
 let roles:[CandidateRLE.ComponentRole]=c.components==1 ? [.grey]:(c.colour=="rgb" ? [.red,.green,.blue]:[.uninterpreted("Y"),.uninterpreted("Cb"),.uninterpreted("Cr")])
 let frame=try CandidateRLE.RLEFrameDescriptor(width:c.width,height:c.height,storageBits:c.sampleBytes*8,meaningfulBits:c.bits,byteOrder:c.big ? .bigEndian:.littleEndian,components:roles,colour:c.components==1 ? .greyscale:(c.colour=="rgb" ? .rgb:.unknown),planarConfiguration:c.planar,rowBytes:c.rowBytes,offset:c.offset)
 image=try CandidateRLE.ImageDestination.allocate(descriptor:frame.imageDescriptor).write { out in
 out.initializeMemory(as:UInt8.self,repeating:0xA5)
 for plane in frame.imageDescriptor.planes {for (ci,component) in plane.components.enumerated(){for y in 0..<c.height{for x in 0..<c.width{
 let i=plane.offset+y*plane.rowBytes+x*plane.pixelStride+ci*plane.sampleStride;let v=value(c,component,x,y)
 out[i]=UInt8(truncatingIfNeeded:c.big && c.sampleBytes==2 ? v>>8:v);if c.sampleBytes==2{out[i+1]=UInt8(truncatingIfNeeded:c.big ? v:v>>8)}
 }}}}
 }
 encoder=try CandidateRLE.Encoder();decoder=try CandidateRLE.Decoder();options=CandidateRLE.DecodeOptions(codecOptions:try CandidateRLE.CodecOptions(frameDescriptor:frame));encoded=try encoder.encodeSynchronously(image).data
 }
 func encode()throws->CandidateRLE.EncodedImage {try encoder.encodeSynchronously(image)}
 func decode()throws->CandidateRLE.DecodedImage {try decoder.decodeSynchronously(encoded,options:options)}
}
struct Previous {
 let input:Data;let encoded:Data;let descriptor:PixelDataDescriptor;let codec=RLECodec();let configuration=CompressionConfiguration()
 init(_ c:Case)throws {
 input=packed(c);descriptor=PixelDataDescriptor(columns:c.width,rows:c.height,bitsAllocated:c.sampleBytes*8,samplesPerPixel:c.components,planarConfiguration:c.planar)
 encoded=try codec.encodeFrame(input,descriptor:descriptor,frameIndex:0,configuration:configuration)
 guard try codec.decodeFrame(encoded,descriptor:descriptor,frameIndex:0)==input else {throw NSError(domain:"PredecessorFidelity",code:1)}
 }
 func encode()throws->Data{try codec.encodeFrame(input,descriptor:descriptor,frameIndex:0,configuration:configuration)}
 func decode()throws->Data{try codec.decodeFrame(encoded,descriptor:descriptor,frameIndex:0)}
}
func emit(_ object:[String:Any])throws { print(String(data:try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]),encoding:.utf8)!);fflush(stdout) }
func caseObject(_ c:Case)throws->Any {try JSONSerialization.jsonObject(with:JSONEncoder().encode(c))}
let args=CommandLine.arguments
func argument(_ key:String)->String? {guard let i=args.firstIndex(of:key),i+1<args.count else{return nil};return args[i+1]}
let smoke=args.contains("--quick")
var cases:[Case]=[]
for (w,h) in (smoke ? [(17,13)] : [(1,1),(17,13),(512,512),(2048,2048),(3072,3072)]) {
 for bits in [8,12,16] {for pattern in ["flat","ramp","noisy"] {
 // Large cases select one pattern per precision rather than a costly Cartesian product.
 if w>=2048 && pattern != (bits==8 ? "flat":(bits==12 ? "ramp":"noisy")) {continue}
 cases.append(Case(width:w,height:h,bits:bits,pattern:pattern,padded:false,big:false,components:1,planar:0,colour:"mono"))
 if bits>8 && (w<2048 ? pattern=="ramp":w==2048) {cases.append(Case(width:w,height:h,bits:bits,pattern:pattern,padded:true,big:bits==16,components:1,planar:0,colour:"mono"))}
 }}
}
for (w,h) in (smoke ? [(17,13)] : [(17,13),(512,512),(2048,2048)]) {
 for bits in [8,16] {for planar in [0,1] {
 cases.append(Case(width:w,height:h,bits:bits,pattern:planar==0 ? "noisy":"ramp",padded:planar==1,big:bits==16,components:3,planar:planar,colour:"rgb"))
 }}
 cases.append(Case(width:w,height:h,bits:8,pattern:"flat",padded:true,big:false,components:3,planar:0,colour:"ybrFull"))
}
if args.contains("--list") {for c in cases{try emit(["id":c.identifier,"case":try caseObject(c)])};exit(0)}
if let selected=argument("--case") {cases=cases.filter{$0.identifier==selected};guard cases.count==1 else{fputs("Unknown or ambiguous case\n",stderr);exit(2)}}
let predecessorValidationOnly=args.contains("--validate-predecessor")
if predecessorValidationOnly {
 cases=cases.filter{!$0.padded && !$0.big}
 guard !cases.isEmpty else{fputs("No predecessor-supported cases\n",stderr);exit(2)}
}
let clock=ContinuousClock()
for c in cases {
 if let implementation=argument("--memory") {
  guard ["candidate","baseline","predecessor"].contains(implementation), ["encode","decode"].contains(argument("--operation") ?? "decode") else{fputs("Invalid memory operation/implementation\n",stderr);exit(2)}
  // Fresh process per case/implementation/operation: absolute process peak includes
  // executable, fixture construction and compressed input preparation, not just codec.
  let op=argument("--operation") ?? "decode"
  let before=bench_memory();var report:[String:Any]=[:]
  if implementation=="candidate" {let a=try Candidate(c);let setup=bench_memory();let counts=try CandidateRLE.BenchmarkTelemetry.measure {if op=="encode"{_ = try a.encode()}else{_ = try a.decode()}};report=["setupPeakRSSBytes":setup.peak_rss_bytes,"owned":counts]}
  else if implementation=="baseline" {let b=try Scalar(c);let setup=bench_memory();let counts=try BaselineRLE.BenchmarkTelemetry.measure {if op=="encode"{_ = try b.encode()}else{_ = try b.decode()}};report=["setupPeakRSSBytes":setup.peak_rss_bytes,"owned":counts]}
  else {let p=try Previous(c);let setup=bench_memory();if op=="encode"{_ = try p.encode()}else{_ = try p.decode()};report=["setupPeakRSSBytes":setup.peak_rss_bytes,"owned":"unavailable: pinned predecessor does not instrument pixel allocator"]}
  let after=bench_memory();report.merge(["case":try caseObject(c),"id":c.identifier,"implementation":implementation,"operation":op,"initialPeakRSSBytes":before.peak_rss_bytes,"peakRSSBytes":after.peak_rss_bytes,"mallocLiveBytes":after.malloc_live_bytes,"mallocLiveBlocks":after.malloc_live_blocks,"mallocMaxBytes":after.malloc_max_bytes,"measurement":"ordinary build; fresh process absolute peak including setup; malloc is process-zone snapshot, not cumulative allocation count"],uniquingKeysWith:{$1});try emit(report);continue
 }
 let b=try Scalar(c),a=try Candidate(c)
 guard b.encoded==a.encoded else{fatalError("scalar encoded differential \(c.identifier)")}
 let decodedB=try b.decode(),decodedA=try a.decode()
 let bytesB=try decodedB.image.storage.withUnsafeBytes{Data($0)},bytesA=try decodedA.image.storage.withUnsafeBytes{Data($0)}
 guard bytesB==bytesA else{fatalError("scalar decoded differential \(c.identifier)")}
 // Independently walk logical coordinates: no expected digest borrowed from decoder.
 try decodedA.image.storage.withUnsafeBytes { p in
 for plane in decodedA.image.descriptor.planes {for (ci,component) in plane.components.enumerated(){for y in 0..<c.height{for x in 0..<c.width{
 let i=plane.offset+y*plane.rowBytes+x*plane.pixelStride+ci*plane.sampleStride
 let actual=c.sampleBytes==1 ? UInt16(p[i]):(c.big ? UInt16(p[i])<<8|UInt16(p[i+1]):UInt16(p[i])|UInt16(p[i+1])<<8)
 guard actual==value(c,component,x,y) else{fatalError("expected sample mismatch")}
 }}}}
 }
 let p:Previous? = (!c.padded && !c.big) ? try Previous(c):nil
 // Untimed cross-decoder proof. Previous.init's self-roundtrip is only a screen;
 // the final successor decoder must agree with independently derived coordinates.
 if let p {
  let cross=try a.decoder.decodeSynchronously(p.encoded,options:a.options)
  var verifiedSamples=0
  try cross.image.storage.withUnsafeBytes { bytes in
   for plane in cross.image.descriptor.planes {for (ci,component) in plane.components.enumerated(){for y in 0..<c.height{for x in 0..<c.width{
    let i=plane.offset+y*plane.rowBytes+x*plane.pixelStride+ci*plane.sampleStride
    let actual=c.sampleBytes==1 ? UInt16(bytes[i]):(c.big ? UInt16(bytes[i])<<8|UInt16(bytes[i+1]):UInt16(bytes[i])|UInt16(bytes[i+1])<<8)
    guard actual==value(c,component,x,y) else{fatalError("predecessor cross-decoder coordinate mismatch")}
    verifiedSamples+=1
   }}}}
  }
  guard verifiedSamples==c.width*c.height*c.components else{fatalError("incomplete predecessor sample traversal")}
  if predecessorValidationOnly {
   let storage=try cross.image.storage.withUnsafeBytes{Data($0)}
   try emit(["id":c.identifier,"case":try caseObject(c),"verifiedLogicalSamples":verifiedSamples,"inputSHA256":digest(packed(c)),"predecessorEncodedSHA256":digest(p.encoded),"predecessorEncodedBytes":p.encoded.count,"finalDecoderStorageSHA256":digest(storage),"candidateEncodedSHA256":digest(a.encoded),"predecessorMatchesCandidateBytes":p.encoded==a.encoded,"validation":"untimed final SwiftRLE cross-decode plus every coordinate-derived logical value; predecessor self-roundtrip supplementary only"])
   continue
  }
 }
 if let rawBatch=argument("--batch-count") {
  guard let count=Int(rawBatch),(1...10000).contains(count) else{exit(2)}
  for op in ["encode","decode"] {
   var bs:[Double]=[],cs:[Double]=[];var checksum=0
   for iteration in 0..<25 {for which in (iteration%2==0 ? [0,1]:[1,0]) {
    let elapsed:Double
    if which==0 {
     if op=="encode" {var results:[BaselineRLE.EncodedImage]=[];results.reserveCapacity(count);let start=clock.now;for _ in 0..<count{results.append(try b.encode())};elapsed=seconds(clock.now-start)/Double(count);checksum ^= results.last!.data.count;withExtendedLifetime(results){} }
     else {var results:[BaselineRLE.DecodedImage]=[];results.reserveCapacity(count);let start=clock.now;for _ in 0..<count{results.append(try b.decode())};elapsed=seconds(clock.now-start)/Double(count);checksum ^= results.last!.image.storage.byteCount;withExtendedLifetime(results){} }
    } else {
     if op=="encode" {var results:[CandidateRLE.EncodedImage]=[];results.reserveCapacity(count);let start=clock.now;for _ in 0..<count{results.append(try a.encode())};elapsed=seconds(clock.now-start)/Double(count);checksum ^= results.last!.data.count;withExtendedLifetime(results){} }
     else {var results:[CandidateRLE.DecodedImage]=[];results.reserveCapacity(count);let start=clock.now;for _ in 0..<count{results.append(try a.decode())};elapsed=seconds(clock.now-start)/Double(count);checksum ^= results.last!.image.storage.byteCount;withExtendedLifetime(results){} }
    }
    if iteration>=5{if which==0{bs.append(elapsed)}else{cs.append(elapsed)}}
   }}
   try emit(["id":c.identifier,"case":try caseObject(c),"operation":op,"baseline":bs,"candidate":cs,"batchCount":count,"warmups":5,"iterations":20,"checksum":checksum,"timing":"per-call batch mean; typed result arrays reserved before timer and retain every output through stop; append/retention costs included symmetrically; all destruction outside timer"])
  };continue
 }
 let orders=[[0,1,2],[1,2,0],[2,0,1],[0,2,1],[2,1,0],[1,0,2]]
 for op in ["encode","decode"] {
 var samples=[[Double](),[Double](),[Double]()];var checksum=0
 for iteration in 0..<25 {
  for implementation in orders[iteration%orders.count] {
   if implementation==0 {guard let p else{continue}
    if op=="encode" {let start=clock.now;let result=try p.encode();let elapsed=seconds(clock.now-start);checksum ^= result.count;if iteration>=5{samples[0].append(elapsed)};withExtendedLifetime(result){} }
    else {let start=clock.now;let result=try p.decode();let elapsed=seconds(clock.now-start);checksum ^= result.count;if iteration>=5{samples[0].append(elapsed)};withExtendedLifetime(result){} }
   }
   else if implementation==1 {
    if op=="encode" {let start=clock.now;let result=try b.encode();let elapsed=seconds(clock.now-start);checksum ^= result.data.count;if iteration>=5{samples[1].append(elapsed)};withExtendedLifetime(result){} }
    else {let start=clock.now;let result=try b.decode();let elapsed=seconds(clock.now-start);checksum ^= result.image.storage.byteCount;if iteration>=5{samples[1].append(elapsed)};withExtendedLifetime(result){} }
   } else {
    if op=="encode" {let start=clock.now;let result=try a.encode();let elapsed=seconds(clock.now-start);checksum ^= result.data.count;if iteration>=5{samples[2].append(elapsed)};withExtendedLifetime(result){} }
    else {let start=clock.now;let result=try a.decode();let elapsed=seconds(clock.now-start);checksum ^= result.image.storage.byteCount;if iteration>=5{samples[2].append(elapsed)};withExtendedLifetime(result){} }
   }
  }
 }
 try emit(["case":try caseObject(c),"id":c.identifier,"operation":op,"predecessor":samples[0],"baseline":samples[1],"candidate":samples[2],"predecessorExclusion":p==nil ? "padded or big-endian storage unsupported by predecessor API":"none; decoded logical fidelity independently checked; codestream identity not required across migration","predecessorEncodedBytes":p?.encoded.count as Any? ?? NSNull(),"encodedBytes":a.encoded.count,"scalarEncodedBytes":b.encoded.count,"logicalBytes":c.logicalBytes,"storageBytes":a.image.storage.byteCount,"inputSHA256":digest(packed(c)),"encodedSHA256":digest(a.encoded),"decodedStorageSHA256":digest(bytesA),"warmups":5,"iterations":20,"checksum":checksum,"timing":"codec call only; result retained through stop; six rotating implementation orders"])
 }
}
