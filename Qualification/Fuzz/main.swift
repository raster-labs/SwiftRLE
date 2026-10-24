// SPDX-License-Identifier: Apache-2.0
// Bounded deterministic mutation engine; deliberately not called coverage-guided.
// Compile with the shipped library sources and NRRD.swift as module SwiftRLE.
import Foundation

struct CLIError: Error { let code:Int; init(_ code:Int) { self.code=code } }
struct RunnerIOError: Error, CustomStringConvertible {
    let stage: String
    let underlying: Error
    var description: String { "CLI runner \(stage): \(underlying)" }
}
// Foundation Process/Pipe may create autoreleased objects on Darwin. Bound
// their lifetime to one synthetic case instead of the complete hour-long run.
func withIterationPool<T>(_ body: () throws -> T) rethrows -> T {
    #if canImport(ObjectiveC)
    return try autoreleasepool(invoking: body)
    #else
    return try body()
    #endif
}
struct Generator {
    var state:UInt64 = 0x524C455234
    mutating func next()->UInt64 { state ^= state << 13;state ^= state >> 7;state ^= state << 17;return state }
    mutating func int(_ bound:Int)->Int { Int(next() % UInt64(bound)) }
}
final class Counters {
    var values:[String:Int]=[:]
    func run<T>(_ name:String, valid:Bool, _ body:() throws -> T) {
        values[name+".cases",default:0]+=1
        do { _ = try body(); values[name+".success",default:0]+=1 }
        catch { values[name+".refused",default:0]+=1;if valid { fatalError("Valid fuzz seed refused at \(name): \(error)") } }
    }
}
func sliced(_ data:Data)->Data { (Data([19,23,29])+data).dropFirst(3) }
func mutate(_ source:Data,_ rng:inout Generator)->Data {
    var data=source
    switch rng.int(5) {
    case 0: data=Data(data.prefix(rng.int(data.count+1)))
    case 1: if !data.isEmpty { data[rng.int(data.count)] ^= UInt8(truncatingIfNeeded:rng.next()) }
    case 2: data.append(contentsOf:repeatElement(UInt8(128),count:rng.int(130)))
    case 3: data=Data((0..<rng.int(300)).map{_ in UInt8(truncatingIfNeeded:rng.next())})
    default: break
    }
    return data
}
func packbits(_ rng:inout Generator,_ counts:Counters,_ limits:ResourceLimits) throws {
    let width=rng.int(130);let height=width==0 ? 0:1+rng.int(3)
    let raw=Data((0..<(width*height)).map{_ in UInt8(truncatingIfNeeded:rng.next())})
    let encoded=try PackBitsEncoder().encode(raw,rowBytes:width,rowCount:height).data
    let valid=rng.int(2)==0, input=valid ? encoded:mutate(encoded,&rng)
    let options=DecodeOptions(resourceLimits:limits), decoder=try PackBitsDecoder()
    counts.run("whole",valid:valid) { let r=try decoder.decode(sliced(input),expectedByteCount:raw.count,options:options);if valid { precondition(r.data==raw) } }
    counts.run("rows",valid:valid) { let r=try decoder.decode(sliced(input),expectedByteCount:raw.count,rowBytes:width,rowCount:height,options:options);if valid { precondition(r.data==raw) } }
    counts.run("chunkCollection",valid:valid) {
        let chunks=stride(from:0,to:input.count,by:7).map { sliced(Data(input[$0..<min(input.count,$0+7)])) }
        let r=try decoder.decodeIncremental(chunks,expectedByteCount:raw.count,rowBytes:width,rowCount:height,options:options);if valid { precondition(r.data==raw) }
    }
    counts.run("sessionFinalization",valid:valid) {
        var session=try decoder.makeIncrementalSession(expectedByteCount:raw.count,options:options)
        for i in stride(from:0,to:input.count,by:3) { try session.append(sliced(Data(input[i..<min(input.count,i+3)]))) }
        let r=try session.finish();if valid { precondition(r.data==raw) }
        do { _=try session.finish();preconditionFailure("Session published twice") } catch is CodecError {}
    }
    counts.run("geometry",valid:false) { _=try decoder.makeIncrementalSession(expectedByteCount:rng.int(400),rowBytes:rng.int(130),rowCount:rng.int(8),options:options) }
}
func fixture(_ planes:[[UInt8]])->Data {
    var out=Data(count:64)
    func word(_ v:Int,_ slot:Int) { for n in 0..<4 { out[slot*4+n]=UInt8(truncatingIfNeeded:v >> (8*n)) } }
    word(planes.count,0)
    for (i,plane) in planes.enumerated() { word(out.count,i+1);out.append(contentsOf:plane) }
    return out
}
func dicom(_ rng:inout Generator,_ counts:Counters,_ limits:ResourceLimits) throws {
    let width=1+rng.int(33),height=1+rng.int(4),bits=[8,12,16][rng.int(3)],storage=bits==8 ? 8:16
    let kind=rng.int(4),components=kind==1 || kind==2 ? 3:1
    let signed=kind==0 && rng.int(2)==0,big=rng.int(2)==0,planar=components==3 && rng.int(2)==0
    let roles:[ComponentRole]=kind==1 ? [.red,.green,.blue]:(kind==2 ? [.uninterpreted("Y"),.uninterpreted("Cb"),.uninterpreted("Cr")]:(kind==3 ? [.uninterpreted("palette-index")]:[.grey]))
    let sampleBytes=storage/8,pixelStride=(planar ? 1:components)*sampleBytes+2,rowBytes=width*pixelStride+6
    var planeList:[PlaneDescriptor]=[]
    for plane in 0..<(planar ? components:1) {
        let origin=2+plane*(rowBytes*height+10)
        planeList.append(try PlaneDescriptor(width:width,height:height,components:planar ? [plane]:Array((0..<components).reversed()),offset:origin,sampleStride:sampleBytes,pixelStride:pixelStride,rowBytes:rowBytes,byteCount:origin+rowBytes*height))
    }
    let descriptor=try ImageDescriptor(width:width,height:height,sampleType:signed ? .signedInteger:.unsignedInteger,storageBits:storage,meaningfulBits:bits,byteOrder:big ? .bigEndian:.littleEndian,components:roles,colour:kind==1 ? .rgb:(kind==0 ? .greyscale:.unknown),planes:planeList,limits:limits)
    let frame=try RLEFrameDescriptor(imageDescriptor:descriptor,limits:limits)
    counts.values["profile.\(kind).\(planar ? "planar":"interleaved").cases",default:0]+=1
    var samples:[UInt16]=[]
    for _ in 0..<(width*height*components) {samples.append(UInt16(truncatingIfNeeded:rng.next()) & (storage==8 ? 255:65535))}
    var planes:[[UInt8]]=[]
    for segment in 0..<(storage/8*components) {
        let component=segment/(storage/8),lane=segment%(storage/8)
        var p:[UInt8]=[]
        for y in 0..<height { p.append(UInt8(width-1));for x in 0..<width { p.append(UInt8(truncatingIfNeeded:samples[(y*width+x)*components+component] >> (8*(storage/8-1-lane)))) } }
        if p.count % 2 != 0 { p.append(0) };planes.append(p)
    }
    let seed=fixture(planes),valid=rng.int(2)==0,input=sliced(valid ? seed:mutate(seed,&rng))
    let options=DecodeOptions(resourceLimits:limits,codecOptions:try CodecOptions(frameDescriptor:frame)),decoder=try Decoder()
    func verify(_ owner:any ReadOnlyImageStorage,canonical:Bool) throws {
        try owner.withUnsafeBytes { bytes in
            let mask=(UInt32(1)<<bits)-1
            var touched=Set<Int>()
            for c in 0..<components {
             let plane=descriptor.planes.first{$0.components.contains(c)}!
             let ci=plane.components.firstIndex(of:c)!
             for y in 0..<height { for x in 0..<width {
                let p=plane.offset+y*plane.rowBytes+x*plane.pixelStride+ci*plane.sampleStride
                for n in 0..<(storage/8) {touched.insert(p+n)}
                let value=storage==8 ? UInt16(bytes[p]):try loadUInt16(bytes,at:p,order:frame.byteOrder)
                var expected=UInt32(samples[(y*width+x)*components+c])
                if canonical { expected &= mask;if signed && expected & (UInt32(1)<<(bits-1)) != 0 {expected |= (storage==8 ? 255:65535)^mask} }
                precondition(UInt32(value)==expected,"sample mismatch")
            }}}
            for p in 0..<bytes.count where !touched.contains(p) {precondition(bytes[p]==0,"padding changed")}
        }
    }
    counts.run("allocatingCanonical",valid:valid) { let r=try decoder.decodeSynchronously(input,options:options);if valid {try verify(r.image.storage,canonical:true)} }
    counts.run("callerDestination",valid:valid) {
        let destination=try ImageDestination.allocate(descriptor:frame.imageDescriptor,limits:limits)
        let r:DecodedImage
        do {r=try decoder.decodeSynchronously(input,into:destination,options:options)}
        catch {
            let beganExpected=(try? DICOMRLEHeader(input,expectedSegmentCount:storage/8*components)) != nil
            do {_=try decoder.decodeSynchronously(seed,into:destination,options:options);precondition(!beganExpected,"Failed write remained reusable");counts.values["callerRefusal.reusable",default:0]+=1}
            catch {precondition(beganExpected,"Preflight failure invalidated destination");counts.values["callerRefusal.invalidated",default:0]+=1}
            throw error
        }
        precondition(r.image.storage.allocationID==destination.storage.allocationID)
        if valid {try verify(r.image.storage,canonical:true)}
        do { _=try decoder.decodeSynchronously(input,into:destination,options:options);preconditionFailure("Sealed destination reused") } catch is CodecError {}
    }
    counts.run("rawAllocatedCells",valid:valid) { let r=try DICOMRLEFrame.decodeAllocatedCells(input,descriptor:frame,options:options);if valid {try verify(r.storage,canonical:false)} }
    counts.run("inspect",valid:valid) { _=try decoder.inspect(input,options:options) }
    counts.run("header",valid:valid) { _=try DICOMRLEHeader(input,expectedSegmentCount:storage/8*components) }
    counts.run("externalDescriptor",valid:false) { _=try RLEFrameDescriptor(width:rng.int(100)-2,height:rng.int(20)-2,storageBits:[0,8,16,32][rng.int(4)],meaningfulBits:rng.int(20),rowBytes:rng.int(200),offset:rng.int(10)-1,limits:limits) }
}
func nrrd(_ rng:inout Generator,_ counts:Counters,_ limits:ResourceLimits) throws {
    let width=1+rng.int(40),height=1+rng.int(5),big=rng.int(2)==0
    let header=Data("NRRD0005\ntype: ushort\ndimension: 2\nsizes: \(width) \(height)\nencoding: raw\nendian: \(big ? "big":"little")\n\n".utf8)
    let pixels=Data((0..<(width*height*2)).map{_ in UInt8(truncatingIfNeeded:rng.next())})
    let valid=rng.int(2)==0,input=valid ? header+pixels:mutate(header+pixels,&rng)
    counts.run("headerPayload",valid:valid) { let r=try NRRD.parse(input,limits:limits);if valid {precondition(r.1==pixels && r.0.width==width && r.0.height==height)} }
    counts.run("slicedHeaderPayload",valid:valid) { let r=try NRRD.parse(sliced(input),limits:limits);if valid {precondition(r.1==pixels)} }
    if let executable=ProcessInfo.processInfo.environment["SWIFTRLE_FUZZ_CLI"] {
        counts.run("cliRouting",valid:valid) {
            let process=Process(),stdin=Pipe(),stdout=Pipe(),stderr=Pipe()
            // Process owns its child-facing ends after launch. The runner owns
            // these three parent-facing handles and closes them every case,
            // including a failed launch/write/read.
            defer {
                try? stdin.fileHandleForWriting.close()
                try? stdout.fileHandleForReading.close()
                try? stderr.fileHandleForReading.close()
            }
            process.executableURL=URL(fileURLWithPath:"/usr/bin/python3")
            process.arguments=[ProcessInfo.processInfo.environment["SWIFTRLE_FUZZ_WATCHDOG"]!,executable,"encode","--input","-","--input-format","nrrd","--output-format","dicom-rle-frame","--output","-","--timeout","1","--max-memory","65536"]
            process.standardInput=stdin;process.standardOutput=stdout;process.standardError=stderr
            do { try process.run() } catch { throw RunnerIOError(stage: "launch", underlying: error) }
            do { try stdin.fileHandleForWriting.write(contentsOf:input) }
            catch { if process.isRunning { process.terminate() }; process.waitUntilExit(); throw RunnerIOError(stage: "write stdin", underlying: error) }
            do { try stdin.fileHandleForWriting.close() }
            catch { if process.isRunning { process.terminate() }; process.waitUntilExit(); throw RunnerIOError(stage: "close stdin", underlying: error) }
            let output=stdout.fileHandleForReading.readDataToEndOfFile();let diagnostics=stderr.fileHandleForReading.readDataToEndOfFile();process.waitUntilExit()
            let text=String(decoding:diagnostics,as:UTF8.self)
            let prefix="SWIFTRLE_CLI_CHILD_PEAK_RSS_BYTES="
            guard let line=text.split(separator:"\n").first(where:{$0.hasPrefix(prefix)}),let rss=Int(line.dropFirst(prefix.count)) else {preconditionFailure("Missing CLI child RSS")}
            counts.values["cliRSS.peakBytes"]=max(counts.values["cliRSS.peakBytes",default:0],rss)
            let watchdogPrefix="SWIFTRLE_WATCHDOG_PEAK_RSS_BYTES="
            guard let watchdogLine=text.split(separator:"\n").first(where:{$0.hasPrefix(watchdogPrefix)}),let watchdogRSS=Int(watchdogLine.dropFirst(watchdogPrefix.count)) else {preconditionFailure("Missing watchdog RSS")}
            counts.values["cliWatchdogRSS.peakBytes"]=max(counts.values["cliWatchdogRSS.peakBytes",default:0],watchdogRSS)
            precondition(process.terminationReason == .exit && [0,3,4,5].contains(process.terminationStatus),"CLI unexpected exit")
            counts.values["cliRouting.exit\(process.terminationStatus)",default:0]+=1
            if valid {precondition(process.terminationStatus==0 && output.count>=64)}
            if process.terminationStatus != 0 {throw CLIError(Int(process.terminationStatus))}
        }
    }
    counts.run("headerExport",valid:true) { let frame=try RLEFrameDescriptor(width:width,height:height,byteOrder:big ? .bigEndian:.littleEndian,limits:limits);let exported=try NRRD.header(frame);precondition(exported==header) }
}
@main struct Campaign {
    static func main() throws {
        let args=CommandLine.arguments
        guard args.count==4,let duration=Double(args[2]),duration>0 else { fatalError("mode seconds receipt") }
        let mode=args[1], path=args[3],clock=ContinuousClock(),start=clock.now
        let limits=try ResourceLimits(maximumCompressedBytes:16384,maximumDecodedBytes:16384,maximumWorkspaceBytes:16384,maximumPixels:4096,maximumDimension:4096,maximumFrames:1,maximumMetadataBytes:1024,maximumICCBytes:1024,maximumWorkers:1,deadlineSeconds:1,maximumMemoryBytes:65536)
        var rng=Generator(),iterations=0,lastReceipt=0
        let counts=Counters()
        func checkpoint(_ complete:Bool) throws {
            let elapsed=clock.now-start
            let seconds=Double(elapsed.components.seconds)+Double(elapsed.components.attoseconds)/1e18
            let descriptorDirectory = FileManager.default.fileExists(atPath: "/proc/self/fd") ? "/proc/self/fd" : "/dev/fd"
            if let handles = try? FileManager.default.contentsOfDirectory(atPath: descriptorDirectory) {
                counts.values["runnerFD.latestObserved"] = handles.count
                counts.values["runnerFD.peakObserved"] = max(counts.values["runnerFD.peakObserved",default:0], handles.count)
            }
            let receipt:[String:Any]=["mode":mode,"engine":"bounded deterministic xorshift64 mutation; not coverage-guided","seed":"0x524C455234","generatorState":String(rng.state),"elapsedSeconds":seconds,"requestedSeconds":duration,"iterations":iterations,"surfaceCounts":counts.values,"complete":complete,"coverage":"unavailable; Apple Swift -sanitize=fuzzer unsupported on this compiler; no coverage measurement claimed","descriptorMeasurement":"Sampled after an iteration and autorelease drain; includes the enumeration handle where exposed by the OS; not a kernel high-water count"]
            let data=try JSONSerialization.data(withJSONObject:receipt,options:[.sortedKeys,.prettyPrinted]);try data.write(to:URL(fileURLWithPath:path),options:.atomic)
        }
        repeat {
            try withIterationPool {
                switch mode {case "packbits":try packbits(&rng,counts,limits);case "dicom":try dicom(&rng,counts,limits);case "nrrd":try nrrd(&rng,counts,limits);default:fatalError("unknown mode")}
            }
            iterations+=1
            let elapsed=clock.now-start
            if Int(elapsed.components.seconds)>=lastReceipt+10 {try checkpoint(false);lastReceipt=Int(elapsed.components.seconds)}
        } while clock.now-start < .seconds(duration)
        try checkpoint(true)
    }
}
