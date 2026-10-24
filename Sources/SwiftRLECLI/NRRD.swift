// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftRLE

// Restricted attached/raw profile reviewed against the official specification,
// 2026-10-24, SHA256 43ca6102cc998e0191e225d7954278547d491e29b74a132b3118571d85a8b0d5.
enum NRRD {
    static func parse(_ data: Data, limits: ResourceLimits) throws -> (RLEFrameDescriptor, Data) {
        var cursor = 0, lines = 0, fields: [String:String] = [:], ended = false
        while cursor < data.count {
            guard cursor < 16_384, lines < 64 else { throw CLIError(5) }
            guard let end = data[cursor..<min(data.count, min(16_384,cursor + 1026))].firstIndex(of:10), end - cursor <= 1024, end < 16_384 else { throw CLIError(3) }
            var bytes = data[cursor..<end]; if bytes.last == 13 { bytes = bytes.dropLast() }
            guard bytes.allSatisfy({ ($0 >= 32 && $0 <= 126) || $0 == 9 }), let line = String(data:bytes,encoding:.ascii) else { throw CLIError(3) }
            cursor = end + 1; lines += 1
            if lines == 1 { guard ["NRRD0001","NRRD0002","NRRD0003","NRRD0004","NRRD0005"].contains(line) else { throw CLIError(3) }; continue }
            if line.isEmpty { ended = true; break }
            if line.hasPrefix("#") { continue }
            guard let split = line.range(of:":") else { throw CLIError(3) }
            let key = String(line[..<split.lowerBound]).trimmingCharacters(in:.whitespaces).lowercased(), value = String(line[split.upperBound...]).trimmingCharacters(in:.whitespaces).lowercased()
            guard ["type","dimension","sizes","encoding","endian"].contains(key) else { throw CLIError(4) }
            guard fields[key] == nil, key != "sizes" || fields["dimension"] != nil else { throw CLIError(3) }
            fields[key] = value
        }
        guard ended, fields.count == 5 else { throw CLIError(3) }
        guard ["ushort","unsigned short","unsigned short int","uint16","uint16_t"].contains(fields["type"] ?? ""), fields["dimension"] == "2", fields["encoding"] == "raw", ["little","big"].contains(fields["endian"] ?? "") else { throw CLIError(4) }
        let sizes = (fields["sizes"] ?? "").split(whereSeparator:{$0 == " " || $0 == "\t"})
        guard sizes.count == 2, let width = Int(sizes[0]), let height = Int(sizes[1]), width > 0, height > 0 else { throw CLIError(3) }
        let frame = try RLEFrameDescriptor(width:width,height:height,byteOrder: fields["endian"] == "little" ? .littleEndian : .bigEndian,limits:limits)
        guard data.count - cursor == frame.imageDescriptor.requiredByteCount else { throw CLIError(3) }
        return (frame,Data(data[cursor...]))
    }
    static func header(_ frame: RLEFrameDescriptor) throws -> Data {
        guard frame.sampleType == .unsignedInteger, frame.storageBits == 16, frame.meaningfulBits == 16, frame.colour == .greyscale, frame.samplesPerPixel == 1, frame.imageDescriptor.planes[0].rowBytes == frame.width * 2 else { throw CLIError(4) }
        return Data("NRRD0005\ntype: ushort\ndimension: 2\nsizes: \(frame.width) \(frame.height)\nencoding: raw\nendian: \(frame.byteOrder == .littleEndian ? "little" : "big")\n\n".utf8)
    }
}
