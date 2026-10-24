// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftRLE

struct CLIError: Error { let code: Int32; init(_ code: Int32) { self.code = code } }
struct Arguments {
    var command = "help", values: [String:String] = [:], flags: Set<String> = [], verbosity = 0
    static let switches: Set<String> = ["overwrite", "json", "quiet", "help"]
    static let valued: Set<String> = ["input", "output", "input-format", "output-format", "mode", "backend", "copy-policy", "threads", "max-memory", "timeout", "width", "height", "storage-bits", "meaningful-bits", "sample-type", "components", "colour", "byte-order", "planar-configuration", "row-bytes", "rows", "decoded-bytes"]
    init(_ arguments: [String]) throws {
        var i = 0; var selected = false
        func level(_ s: String) throws -> Int {
            if !s.isEmpty && s.allSatisfy({ $0 == "+" }) && s.count <= 5 { return s.count }
            guard let n = Int(s), (1...5).contains(n) else { throw CLIError(2) }; return n
        }
        while i < arguments.count {
            let a = arguments[i]; i += 1
            if a == "--version" { guard !selected else { throw CLIError(2) }; command = "version"; selected = true; continue }
            if a == "-h" || a == "--help" { flags.insert("help"); continue }
            if a == "-q" || a == "--quiet" { flags.insert("quiet"); continue }
            if a.hasPrefix("-v") && a.dropFirst().allSatisfy({$0 == "v"}) { verbosity += a.count - 1; guard verbosity <= 5 else { throw CLIError(2) }; continue }
            if a == "--verbose" || a == "-verbose" {
                if i < arguments.count && (Int(arguments[i]) != nil || arguments[i].hasPrefix("+")) { verbosity = try level(arguments[i]); i += 1 }
                else { verbosity += 1 }; guard verbosity <= 5 else { throw CLIError(2) }; continue
            }
            if a.hasPrefix("--verbose=") || a.hasPrefix("-verbose:") {
                let sep: Character = a.hasPrefix("--") ? "=" : ":"
                let v = String(a.split(separator: sep, maxSplits: 1, omittingEmptySubsequences: false)[1])
                if v.isEmpty { guard i < arguments.count else { throw CLIError(2) }; verbosity = try level(arguments[i]); i += 1 }
                else { verbosity = try level(v) }; continue
            }
            if !a.hasPrefix("-") {
                if !selected { command = a; selected = true; continue }
                if command == "help" && values["topic"] == nil { values["topic"] = a; continue }
                throw CLIError(2)
            }
            let mapped = a == "-i" ? "--input" : a == "-o" ? "--output" : a
            guard mapped.hasPrefix("--") else { throw CLIError(2) }
            let parts = mapped.dropFirst(2).split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let key = String(parts[0])
            if Self.switches.contains(key) { guard parts.count == 1, !flags.contains(key) else { throw CLIError(2) }; flags.insert(key); continue }
            guard Self.valued.contains(key), values[key] == nil else { throw CLIError(2) }
            if parts.count == 2 { values[key] = String(parts[1]) }
            else { guard i < arguments.count else { throw CLIError(2) }; values[key] = arguments[i]; i += 1 }
        }
        guard ["help","version","capabilities","encode","decode","inspect","validate"].contains(command), !(flags.contains("quiet") && verbosity > 0) else { throw CLIError(2) }
    }
    func integer(_ key: String, default fallback: Int? = nil, zero: Bool = false) throws -> Int {
        if values[key] == nil, let fallback { return fallback }
        guard let s = values[key], let n = Int(s), zero ? n >= 0 : n > 0 else { throw CLIError(2) }; return n
    }
    func validate() throws {
        if let topic = values["topic"], !["encode","decode","inspect","validate","capabilities","version"].contains(topic) { throw CLIError(2) }
        if flags.contains("help") { return }
        if ["help","version","capabilities"].contains(command) { guard values.keys.allSatisfy({$0 == "topic"}) && flags.isSubset(of: ["help","quiet","json"]) else { throw CLIError(2) }; return }
        guard values["input"] != nil, values["input-format"] != nil else { throw CLIError(2) }
        if ["encode","decode"].contains(command) { guard values["output"] != nil, values["output-format"] != nil else { throw CLIError(2) } }
        else { guard values["output"] == nil, values["output-format"] == nil, !flags.contains("overwrite") else { throw CLIError(2) } }
        if command != "encode" && values["mode"] != nil { throw CLIError(2) }
        if let mode = values["mode"], mode != "lossless" { throw CLIError(["near-lossless","lossy"].contains(mode) ? 4 : 2) }
        if let backend = values["backend"], !["automatic","scalar","scalar-cpu","preferred-accelerated","required-accelerated"].contains(backend) { throw CLIError(2) }
        if values["backend"] == "required-accelerated" { throw CLIError(4) }
        if let policy = values["copy-policy"], !["require-sharing","allow-copy"].contains(policy) { throw CLIError(2) }
        _ = try integer("threads", default: 2)
        if let timeout = values["timeout"] { guard let n = Double(timeout), n.isFinite, n > 0, n <= 120 else { throw CLIError(2) } }
        _ = try integer("max-memory", default: 1_073_741_824)
        let input = values["input-format"] ?? "", output = values["output-format"] ?? ""
        guard ["raw","packbits","dicom-rle-frame","nrrd"].contains(input), output.isEmpty || ["raw","packbits","dicom-rle-frame","nrrd"].contains(output) else { throw CLIError(4) }
        let pack = input == "packbits" || output == "packbits"
        if pack {
            guard (command == "encode" && input == "raw" && output == "packbits") || (command != "encode" && input == "packbits" && (output.isEmpty || output == "raw")) else { throw CLIError(2) }
            let imageKeys: Set<String> = ["width","height","storage-bits","meaningful-bits","sample-type","components","colour","byte-order","planar-configuration"]
            guard imageKeys.isDisjoint(with: values.keys) else { throw CLIError(2) }
            if command != "encode" { _ = try integer("decoded-bytes", zero: true) }
            else if values["decoded-bytes"] != nil { throw CLIError(2) }
            if values["row-bytes"] != nil || values["rows"] != nil {
                let a = try integer("row-bytes"), b = try integer("rows"); let (n, overflow) = a.multipliedReportingOverflow(by:b)
                guard !overflow, try command == "encode" || n == integer("decoded-bytes",zero:true) else { throw CLIError(2) }
            }
        } else {
            guard values["decoded-bytes"] == nil, values["rows"] == nil else { throw CLIError(2) }
            guard command == "encode" ? (["raw","nrrd"].contains(input) && output == "dicom-rle-frame") : (input == "dicom-rle-frame" && (output.isEmpty || ["raw","nrrd"].contains(output))) else { throw CLIError(2) }
            if input == "nrrd" {
                let imageKeys: Set<String> = ["width","height","storage-bits","meaningful-bits","sample-type","components","colour","byte-order","planar-configuration","row-bytes"]
                guard imageKeys.isDisjoint(with: values.keys) else { throw CLIError(2) }
            } else { let descriptor = try frame(limits: .default); if output == "nrrd" { _ = try NRRD.header(descriptor) } }
        }
    }
    func frame(limits: ResourceLimits) throws -> RLEFrameDescriptor {
        let width = try integer("width"), height = try integer("height"), storage = try integer("storage-bits"), bits = try integer("meaningful-bits"), count = try integer("components")
        guard let sample = values["sample-type"], ["unsigned","signed"].contains(sample), let order = values["byte-order"], ["little","big"].contains(order), let colour = values["colour"], values["planar-configuration"] != nil else { throw CLIError(2) }
        let roles: [ComponentRole]; let interpretation: ColourInterpretation
        switch colour {
        case "greyscale": roles = [.grey]; interpretation = .greyscale
        case "rgb": roles = [.red,.green,.blue]; interpretation = .rgb
        case "palette": roles = [.uninterpreted("palette-index")]; interpretation = .unknown
        case "ybr-full": roles = [.uninterpreted("Y"),.uninterpreted("Cb"),.uninterpreted("Cr")]; interpretation = .unknown
        default: throw CLIError(4)
        }
        guard roles.count == count else { throw CLIError(2) }
        return try RLEFrameDescriptor(width:width,height:height,sampleType:sample == "unsigned" ? .unsignedInteger : .signedInteger,storageBits:storage,meaningfulBits:bits,byteOrder:order == "little" ? .littleEndian : .bigEndian,components:roles,colour:interpretation,planarConfiguration:integer("planar-configuration",zero:true),rowBytes:values["row-bytes"] == nil ? nil : integer("row-bytes"),limits:limits)
    }
}
