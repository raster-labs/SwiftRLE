// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftRLE

@Suite("Bounded word-scan packet identity and admission")
struct WordScanTests {
    /// Frozen scalar packet policy from the previous optimized candidate.
    /// Uses arrays and byte-by-byte lookahead, with no word loads or bit masks.
    private func scalarPackets(_ input: [UInt8], rowBytes: Int? = nil) -> Data {
        guard !input.isEmpty else { return Data() }
        let width = rowBytes ?? input.count
        var result: [UInt8] = []
        for rowStart in stride(from: 0, to: input.count, by: width) {
            let rowEnd = rowStart + width
            var position = rowStart
            while position < rowEnd {
                var repeats = 1
                while repeats < 128 && repeats < rowEnd - position && input[position + repeats] == input[position] {
                    repeats += 1
                }
                let followedByPair = rowEnd - position >= 4 && input[position + 2] == input[position + 3]
                if repeats >= 3 || (repeats == 2 && (position + 2 == rowEnd || followedByPair)) {
                    result.append(UInt8(257 - repeats))
                    result.append(input[position])
                    position += repeats
                } else {
                    let first = position
                    position += repeats
                    while position < rowEnd && position - first < 128 {
                        if rowEnd - position >= 2 && input[position] == input[position + 1] {
                            let terminalPair = rowEnd - position == 2
                            let triple = rowEnd - position >= 3 && input[position] == input[position + 2]
                            let adjacentPair = rowEnd - position >= 4 && input[position + 2] == input[position + 3]
                            if terminalPair || triple || adjacentPair { break }
                        }
                        position += 1
                    }
                    result.append(UInt8(position - first - 1))
                    result.append(contentsOf: input[first..<position])
                }
            }
        }
        return Data(result)
    }

    private func check(_ input: Data, rowBytes: Int? = nil) throws {
        let rows = rowBytes.map { input.count / $0 }
        let encoded = try PackBitsEncoder().encode(input, rowBytes: rowBytes, rowCount: rows)
        #expect(encoded.data == scalarPackets(Array(input), rowBytes: rowBytes))
        let decoded = try PackBitsDecoder().decode(encoded.data, expectedByteCount: input.count,
                                                 rowBytes: rowBytes, rowCount: rows)
        #expect(decoded.data == input)
        #expect(decoded.consumedByteCount == encoded.data.count)
    }

    @Test func unalignedInputsAndLiteralPacketTails() throws {
        // External backing storage lets each 0...7 address residue reach loadUnaligned.
        // The allocation ends exactly at the input end so ASan can detect tail overreads.
        for offset in 0..<8 {
            for count in [32, 33, 63, 64, 65, 126, 127, 128, 129, 130, 135, 255, 256, 257] {
                for repeatPosition in [0, 1, 7, 8, 9, 120, 126, 127, 128] {
                    let owner = UnsafeMutableRawPointer.allocate(byteCount: offset + count, alignment: 16)
                    defer { owner.deallocate() }
                    let start = owner.advanced(by: offset).assumingMemoryBound(to: UInt8.self)
                    for index in 0..<count { start[index] = UInt8(truncatingIfNeeded: index * 37 + 11) }
                    if repeatPosition + 3 <= count {
                        start[repeatPosition] = 0xD3
                        start[repeatPosition + 1] = 0xD3
                        start[repeatPosition + 2] = 0xD3
                    }
                    let input = Data(bytesNoCopy: UnsafeMutableRawPointer(start), count: count, deallocator: .none)
                    #expect(input.withUnsafeBytes { Int(bitPattern: $0.baseAddress!) & 7 } == offset)
                    try check(input)
                }
            }
        }
    }

    @Test func zeroByteMaskBorrowAndHighBitPatterns() throws {
        // Construct bytes from chosen adjacent XOR differences. A zero followed
        // by 0x01 values causes borrow propagation in the word zero-byte test.
        // The first matching position must still be selected in input order.
        for zeroPosition in 0..<8 {
            for other in [UInt8(1), 2, 0x7F, 0x80, 0x81, 0xFE, 0xFF] {
                for prefixLength in 0..<8 {
                    var differences = Array(repeating: other, count: 8)
                    differences[zeroPosition] = 0
                    for index in (zeroPosition + 1)..<8 { differences[index] = 1 }
                    // A later genuine triple distinguishes a harmless false mask
                    // bit from accidentally skipping a necessary packet boundary.
                    differences.append(contentsOf: [0x80, 0xFF, 0, 0, 0x7F, 1, 1, 0xFE])
                    var input = (0..<prefixLength).map { UInt8($0 * 19 + 3) }
                    input.append(0xA5)
                    for difference in differences { input.append(input.last! ^ difference) }
                    input.append(contentsOf: (0..<140).map { UInt8(truncatingIfNeeded: $0 * 29) })
                    try check(Data(input))
                }
            }
        }
    }

    @Test func rowTailsDoNotLookIntoNextRow() throws {
        for width in Array(1...17) + Array(120...137) + [255, 256, 257] {
            var input: [UInt8] = []
            for row in 0..<3 {
                var bytes = (0..<width).map { UInt8(truncatingIfNeeded: $0 * 31 + row * 7) }
                // Equal bytes across a row boundary must not merge packets.
                bytes[0] = 0xAA
                bytes[width - 1] = 0xAA
                if width > 2 { bytes[width - 2] = 0xAA }
                input.append(contentsOf: bytes)
            }
            try check(Data(input), rowBytes: width)
        }
    }

    @Test func exactOutputAndAggregateBudgets() throws {
        for count in [9, 17, 127, 128, 129, 257] {
            let input = Data((0..<count).map { UInt8(truncatingIfNeeded: $0 * 37) })
            let expected = scalarPackets(Array(input))
            let exact = try ResourceLimits(maximumCompressedBytes: expected.count,
                                           maximumMemoryBytes: input.count + expected.count)
            #expect(try PackBitsEncoder().encode(input, options: .init(resourceLimits: exact)).data == expected)
            for limits in [
                try ResourceLimits(maximumCompressedBytes: expected.count - 1),
                try ResourceLimits(maximumMemoryBytes: input.count + expected.count - 1)
            ] {
                do {
                    _ = try PackBitsEncoder().encode(input, options: .init(resourceLimits: limits))
                    Issue.record("Expected output/admission limit rejection")
                } catch let error as CodecError {
                    #expect(error.category == .resourceLimitExceeded)
                }
            }
        }
    }
}
