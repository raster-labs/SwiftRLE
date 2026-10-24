// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftRLE

@Suite("DCMTK DICOM RLE two-way oracle")
struct FrameOracleTests {
    @Test func independentDICOMInteroperability() throws {
        #if os(macOS) || os(Linux)
        let repository = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let script = repository.appendingPathComponent("Scripts/dicom-oracle.py")
        let persistent = ProcessInfo.processInfo.environment["SWIFTRLE_ORACLE_OUTPUT"]
        let directory = persistent.map { URL(fileURLWithPath: $0) } ?? FileManager.default.temporaryDirectory.appendingPathComponent("swiftrle-r2-oracle-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { if persistent == nil { try? FileManager.default.removeItem(at: directory) } }
        func run(_ mode: String) throws {
            let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3",script.path,mode,directory.path]
            let log = directory.appendingPathComponent(mode+".log")
            FileManager.default.createFile(atPath: log.path,contents: nil)
            let handle = try FileHandle(forWritingTo: log); defer { try? handle.close() }
            process.standardOutput = handle; process.standardError = handle
            try process.run(); process.waitUntilExit()
            guard process.terminationStatus == 0 else {
                throw CodecError(.ioFailure,"Required DCMTK oracle failed: \(try String(contentsOf: log,encoding: .utf8))")
            }
        }
        try run("prepare")
        struct Manifest: Decodable { let cases: [Case] }
        struct Case: Decodable { let name: String; let photo: String; let components: Int; let bits: Int; let precision: Int; let signed: Bool; let planar: Int }
        let cases = try JSONDecoder().decode(Manifest.self,from: Data(contentsOf: directory.appendingPathComponent("oracle.json"))).cases
        #expect(cases.count >= 20)
        for item in cases {
            let roles: [ComponentRole] = item.photo == "RGB" ? [.red,.green,.blue] : item.photo == "YBR_FULL" ? [.uninterpreted("Y"),.uninterpreted("Cb"),.uninterpreted("Cr")] : item.photo == "PALETTE COLOR" ? [.uninterpreted("palette-index")] : [.grey]
            let colour: ColourInterpretation = item.photo == "RGB" ? .rgb : item.photo.hasPrefix("MONO") ? .greyscale : .unknown
            let frame = try RLEFrameDescriptor(width: 3,height: 2,sampleType: item.signed ? .signedInteger : .unsignedInteger,
                storageBits: item.bits,meaningfulBits: item.precision,components: roles,colour: colour,planarConfiguration: item.planar)
            func value(_ c: Int,_ x: Int,_ y: Int) -> UInt16 {
                let mask = (1 << item.precision)-1
                let v = [0,mask,1,1 << (item.precision-1),mask-1,0x53][(x+y*3+c)%6] & mask
                return UInt16(item.signed && v & (1 << (item.precision-1)) != 0 ? v | ((item.bits == 8 ? 255 : 65535) ^ mask) : v)
            }
            let bytes = try Data(contentsOf: directory.appendingPathComponent(item.name+".rle"))
            let decoded = try Decoder().decodeSynchronously(bytes,options: FrameTests.options(frame))
            try decoded.image.storage.withUnsafeBytes { (b: UnsafeRawBufferPointer) throws -> Void in
                for y in 0..<2 { for x in 0..<3 { for c in roles.indices { #expect(try FrameTests.cell(b,frame.imageDescriptor,c,x,y) == value(c,x,y)) } } }
            }
            let source = try FrameTests.source(frame,value: value)
            let encoded = try Encoder().encodeSynchronously(source)
            try encoded.data.write(to: directory.appendingPathComponent(item.name+"-swift.rle"))
        }
        try run("verify")
        print("DCMTK two-way oracle passed \(cases.count) synthetic profiles with independently checked embedding/extraction.")
        #endif
    }
}
