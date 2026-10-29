// SPDX-License-Identifier: Apache-2.0
import Foundation
import Dispatch
import SwiftRLE
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

package struct Main {
    static let version = "1.0.0"
    static let help = """
    swiftrle-cli 1.0.0 — PackBits and DICOM RLE frame codec
    Usage: swiftrle-cli <encode|decode|inspect|validate|capabilities> [options]
    Help: -h, --help, help [command]; version: --version, version; no arguments: help.
    encode: raw -> packbits; raw/nrrd -> dicom-rle-frame.
    decode: packbits -> raw; dicom-rle-frame -> raw/nrrd.
    inspect/validate: packbits (requires decoded size) or dicom-rle-frame.
    Required: -i/--input PATH --input-format FORMAT; encode/decode also
      -o/--output PATH --output-format FORMAT. '-' means stdin/stdout.
    DICOM raw endpoints require --width N --height N --storage-bits 8|16
      --meaningful-bits N --sample-type unsigned|signed --components 1|3
      --colour greyscale|rgb|palette|ybr-full --byte-order little|big
      --planar-configuration 0|1. Optional --row-bytes N includes padding.
    These describe EXTERNAL interpretation/layout, never DICOM RLE header fields.
    PackBits decode/inspect/validate require --decoded-bytes N (>=0).
      Optional --row-bytes N --rows N must agree with decoded bytes.
    Shared: --mode lossless (default); --backend automatic|scalar|scalar-cpu|
      preferred-accelerated|required-accelerated; --copy-policy require-sharing|allow-copy
      --threads N (>0, default 2) --max-memory BYTES (>0, default 1073741824)
      --timeout SECONDS (>0, <=120, default 120) --overwrite --json --quiet/-q.
    Verbosity default 0, range 0..5: -v, -vv..-vvvvv, --verbose LEVEL,
      --verbose=LEVEL, -verbose: LEVEL, -verbose:LEVEL; '+'..'+++++' also levels.
      Bare --verbose/-verbose increment. Explicit forms set; repeats increment in order.
      Quiet conflicts with verbosity. Diagnostics never contain paths or payloads.
    NRRD: attached raw 2D unsigned full16 greyscale only, explicit endian;
      rejects detached data, non-raw encoding, extra semantics and 12-in-16 output.
    Binary stdout is payload only; encode/decode JSON reports go to stderr;
      inspect/capabilities JSON go to stdout. Failure may leave partial stdout.
    Files refuse overwrite atomically; --overwrite replaces final output transactionally.
    Exits: 0 success; 2 arguments; 3 malformed; 4 unsupported; 5 limit/deadline;
      6 I/O/storage (including broken pipe); 7 internal; 130 cancellation.
    Examples (payload.bin contains exactly 4096 bytes):
      swiftrle-cli encode -i payload.bin --input-format raw --output-format packbits -o payload.packbits
      swiftrle-cli decode -i payload.packbits --input-format packbits --decoded-bytes 4096 --output-format raw -o restored.bin
    """
    static func helpFor(_ command:String) -> String {
        guard ["encode","decode","inspect","validate","capabilities","version"].contains(command) else { return help }
        let common = "\nHelp: -h/--help; verbosity -v through -vvvvv, --verbose LEVEL, --verbose=LEVEL, -verbose: LEVEL or -verbose:LEVEL (levels1..5 or plus strings); bare --verbose/-verbose increments. --quiet/-q conflicts with verbosity. --json selects structured output. Diagnostics use stderr, exclude paths/private metadata/payload/addresses. Exits:0 success,2 arguments,3 malformed,4 unsupported,5 limit/deadline,6 I/O,7 internal,130 cancellation."
        if command == "version" { return "swiftrle-cli version: prints release version. --quiet/-q preserves requested output. -h/--help shows help." }
        if command == "capabilities" { return "swiftrle-cli capabilities [--json]: reports actual scalar PackBits and DICOM RLE availability and qualified NRRD interchange." + common }
        let input = "\n-i/--input PATH --input-format FORMAT; '-' means stdin. --backend automatic|scalar|scalar-cpu|preferred-accelerated|required-accelerated; --copy-policy require-sharing|allow-copy; --threads N (>0,default2); --max-memory BYTES (>0,default1073741824); --timeout SECONDS (>0,<=120,default120)."
        let frame = "\nDICOM external interpretation/layout: --width N --height N --storage-bits 8|16 --meaningful-bits N --sample-type unsigned|signed --components 1|3 --colour greyscale|rgb|palette|ybr-full --byte-order little|big --planar-configuration 0|1; optional --row-bytes N. These are external semantics, never header discoveries."
        if command == "encode" { return "swiftrle-cli encode: raw -> packbits; raw/nrrd -> dicom-rle-frame.\n-o/--output PATH --output-format packbits|dicom-rle-frame; --mode lossless only (default); --overwrite atomically replaces final output. Optional PackBits --row-bytes N --rows N. NRRD is attached raw2D full16 unsigned grey with explicit endian. Binary stdout only payload; --json reports stderr; failure may leave partial stdout." + input + frame + common }
        if command == "decode" { return "swiftrle-cli decode: packbits -> raw; dicom-rle-frame -> raw/nrrd.\n-o/--output PATH --output-format raw|nrrd; --overwrite atomically replaces final output. PackBits requires --decoded-bytes N (>=0), optional --row-bytes N --rows N with matching product. NRRD requires full16 unsigned grey, packed rows;12-in-16 is rejected. Binary stdout only payload; --json reports stderr; failure may leave partial stdout." + input + frame + common }
        return "swiftrle-cli \(command): explicit packbits or dicom-rle-frame input. Inspect checks frame header against external interpretation; validate decodes complete payload. JSON uses stdout. PackBits requires --decoded-bytes N (>=0), optional --row-bytes N --rows N with matching product." + input + frame + common
    }
    static func message(_ text: String) { let bytes = Data((text + "\n").utf8); try? FileHandle.standardError.write(contentsOf:bytes) }
    package static func executeProcess() async {
        _ = receivedSignal.load(ordering:.relaxed)
        signal(SIGPIPE,SIG_IGN); signal(SIGINT) { receivedSignal.store($0,ordering:.relaxed) }; signal(SIGTERM) { receivedSignal.store($0,ordering:.relaxed) }
        do {
            #if SWIFTRLE_CLI_TESTING
            if ProcessInfo.processInfo.environment["SWIFTRLE_TEST_INTERNAL_FAILURE"] == "1" { throw CodecError(.internalFailure,"Test-only internal failure") }
            #endif
            let args = try Arguments(Array(CommandLine.arguments.dropFirst())); try args.validate()
            let control = Control(seconds:Double(args.values["timeout"] ?? "120") ?? 120)
            let task = Task.detached { try run(args,control:control) }
            let monitor = DispatchSource.makeTimerSource(queue:.global())
            monitor.schedule(deadline:.now(),repeating:.milliseconds(10))
            monitor.setEventHandler { @Sendable in if receivedSignal.load(ordering:.relaxed) != 0 { control.cancelled.store(true,ordering:.relaxed); task.cancel() } }
            monitor.resume()
            defer { monitor.cancel() }
            try await task.value
        } catch {
            let code: Int32
            if let e = error as? CLIError { code = e.code }
            else if error is CancellationError { code = 130 }
            else if let e = error as? CodecError {
                switch e.category {
                case .invalidArgument: code = 2
                case .malformedInput: code = 3
                case .unsupportedFormat,.unsupportedFeature,.incompatibleImageLayout,.backendUnavailable: code = 4
                case .resourceLimitExceeded: code = 5
                case .storageUnavailable,.ioFailure: code = 6
                case .internalFailure: code = 7
                }
            } else { code = 7 }
            message("swiftrle-cli: operation failed (exit \(code))"); exit(code)
        }
    }
    package static func run(
        _ a: Arguments,
        control: Control,
        observeEncodeOptions: ((EncodeOptions) -> Void)? = nil,
        observeDecodeOptions: ((DecodeOptions) -> Void)? = nil
    ) throws {
        let io = StreamIO(control:control)
        var completed=false
        defer {
            if completed && a.verbosity >= 1 { message("swiftrle-cli: completed") }
            if completed && a.verbosity >= 2 { message("swiftrle-cli: stages complete") }
            if completed && a.verbosity >= 3 { message("swiftrle-cli: bounded scalar configuration") }
            if completed && a.verbosity >= 4 { let elapsed=control.started.duration(to:control.now()).components;message("swiftrle-cli: elapsed seconds \(Double(elapsed.seconds)+Double(elapsed.attoseconds)/1e18)") }
            if completed && a.verbosity >= 5 { message("swiftrle-cli: trace: bounded operation and publication complete") }
        }

        if a.command == "help" || a.flags.contains("help") { try io.publish([Data((helpFor(a.values["topic"] ?? a.command)+"\n").utf8)],path:"-",overwrite:false); completed=true; return }
        if a.command == "version" { try io.publish([Data((version+"\n").utf8)],path:"-",overwrite:false); completed=true; return }
        if a.command == "capabilities" {
            let value: [String:Any] = ["version":version,"formats":["packbits","dicom-rle-frame"],"interchange":["nrrd-attached-raw-2d-uint16"],"encode":true,"decode":true,"inspect":true,"externalFrameDescriptorRequired":true,"backends":["scalarCPU"]]
            try io.publish([try JSONSerialization.data(withJSONObject:value,options:[.sortedKeys]),Data([10])],path:"-",overwrite:false); completed=true; return
        }
        let memory = try a.integer("max-memory",default:1_073_741_824), threads = try a.integer("threads",default:2)
        guard memory >= 65_536 else { throw CLIError(5) }
        let ceiling = (memory - 32_768) / 8
        let input = try io.readInput(a.values["input"] ?? "-",maximum:min(256*1024*1024,ceiling))
        let limits = try control.resourceLimits(memory:memory,threads:threads)
        let policy = try a.executionPolicy()
        let copy: CopyPolicy = a.values["copy-policy"] == "allow-copy" ? .allowCopy : .requireSharedStorage
        func currentLimits() throws -> ResourceLimits {
            try control.resourceLimits(memory:memory,threads:threads)
        }
        func encodeOptions() throws -> EncodeOptions {
            let options = try EncodeOptions(resourceLimits:currentLimits(),executionPolicy:policy,copyPolicy:copy)
            observeEncodeOptions?(options)
            return options
        }
        func decodeOptions() throws -> DecodeOptions {
            let options = try DecodeOptions(resourceLimits:currentLimits(),executionPolicy:policy,copyPolicy:copy)
            observeDecodeOptions?(options)
            return options
        }
        let inputFormat = a.values["input-format"] ?? "", outputFormat = a.values["output-format"] ?? ""

        if a.verbosity >= 2 { message("swiftrle-cli: input admitted; codec stage") }
        if a.verbosity >= 3 { message("swiftrle-cli: scalar backend; bounded memory admission; explicit formats") }
        var output: [Data] = [], report: OperationReport?, info: [String:Any] = [:]
        if inputFormat == "packbits" || outputFormat == "packbits" {
            let row = try a.values["row-bytes"] == nil ? nil : a.integer("row-bytes"), rows = try a.values["rows"] == nil ? nil : a.integer("rows")
            if a.command == "encode" {
                let result = try PackBitsEncoder().encode(input,rowBytes:row,rowCount:rows,options:encodeOptions()); output = [result.data]; report = result.report
            } else {
                let result = try PackBitsDecoder().decode(input,expectedByteCount:a.integer("decoded-bytes",zero:true),rowBytes:row,rowCount:rows,options:decodeOptions())
                output = [result.data]; report = result.report; info = ["format":"packbits","decodedBytes":result.data.count,"validated":true]
            }
        } else if a.command == "encode" {
            let frame: RLEFrameDescriptor, pixels: Data
            if inputFormat == "nrrd" { (frame,pixels) = try NRRD.parse(input,limits:limits) }
            else { frame = try a.frame(limits:limits); pixels = input }
            guard pixels.count == frame.imageDescriptor.requiredByteCount else { throw CLIError(3) }
            let destination = try ImageDestination.allocate(descriptor:frame.imageDescriptor,limits:limits)
            let image = try destination.write { bytes in pixels.copyBytes(to:bytes) }
            let result = try Encoder().encodeSynchronously(image,options:encodeOptions()); output = [result.data]; report = result.report
        } else {
            let frame = try a.frame(limits:limits)
            if outputFormat == "nrrd" { _ = try NRRD.header(frame) }
            let decoder = try Decoder(configuration:DecoderConfiguration(codecOptions:CodecOptions(frameDescriptor:frame)))
            let inspected = try decoder.inspect(input,options:decodeOptions())
            info = ["format":"dicom-rle-frame","width":inspected.descriptor.width,"height":inspected.descriptor.height,"meaningfulBits":inspected.descriptor.meaningfulBits,"interpretationSource":"external","headerFields":["segment-count","segment-offsets"]]
            if a.command != "inspect" {
                let decoded = try decoder.decodeSynchronously(input,options:decodeOptions()); report = decoded.report
                if a.command == "decode" {
                    let pixels = try decoded.image.storage.withUnsafeBytes { Data($0) }
                    output = outputFormat == "nrrd" ? [try NRRD.header(frame),pixels] : [pixels]
                }
                info["validated"] = true
            }
        }
        try control.check()
        if ["inspect","validate"].contains(a.command) {
            try io.publish([try JSONSerialization.data(withJSONObject:info,options:[.sortedKeys]),Data([10])],path:"-",overwrite:false)
        } else {
            try io.publish(output,path:a.values["output"] ?? "-",overwrite:a.flags.contains("overwrite"))
            if a.flags.contains("json") { let object: [String:Any] = ["success":true,"backend":"scalarCPU","fallback":report?.fallbackReason as Any? ?? NSNull(),"outputBytes":output.reduce(0,{$0+$1.count})]; message(String(decoding:try JSONSerialization.data(withJSONObject:object,options:[.sortedKeys]),as:UTF8.self)) }
        }

        completed=true
    }
}
