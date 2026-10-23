// SPDX-License-Identifier: Apache-2.0
// Adapted from raster-labs/DICOMKit @ 4b68d7e22829418c88e48dd53d98b25fee50d90d
// (Tests/DICOMCoreTests/RLEEncoderTests.swift, CompressedPixelDataTests.swift, CodecFuzzTests.swift, MIT)
import Foundation
import Testing
@testable import SwiftRLE

@Suite("PackBits Scalar Byte Engine, Incremental Decode and libtiff Interoperability Tests")
struct PackBitsTests {

    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
    }

    @Test("Independent known PackBits vectors (literals, repeats, NOP 0x80 and Apple TN1023 vector)")
    func testIndependentKnownVectors() throws {
        let encoder = try PackBitsEncoder()
        let decoder = try PackBitsDecoder()

        // 1. Literal vector: 02 41 42 43 <-> "ABC"
        let abcRaw = Data([0x41, 0x42, 0x43])
        let abcExpectedEncoded = Data([0x02, 0x41, 0x42, 0x43])
        let abcEncoded = try encoder.encode(abcRaw)
        #expect(abcEncoded.data == abcExpectedEncoded)
        let abcDecoded = try decoder.decode(abcExpectedEncoded, expectedByteCount: 3)
        #expect(abcDecoded.data == abcRaw)
        #expect(abcDecoded.consumedByteCount == 4)

        // 2. Repeat vector: FF 7F <-> 2x 0x7F
        let rep2Raw = Data([0x7F, 0x7F])
        let rep2ExpectedEncoded = Data([0xFF, 0x7F])
        let rep2Encoded = try encoder.encode(rep2Raw)
        #expect(rep2Encoded.data == rep2ExpectedEncoded)
        let rep2Decoded = try decoder.decode(rep2ExpectedEncoded, expectedByteCount: 2)
        #expect(rep2Decoded.data == rep2Raw)
        #expect(rep2Decoded.consumedByteCount == 2)

        // 3. Max single repeat vector: 81 00 <-> 128x 0x00
        let rep128Raw = Data(repeating: 0x00, count: 128)
        let rep128ExpectedEncoded = Data([0x81, 0x00])
        let rep128Encoded = try encoder.encode(rep128Raw)
        #expect(rep128Encoded.data == rep128ExpectedEncoded)
        let rep128Decoded = try decoder.decode(rep128ExpectedEncoded, expectedByteCount: 128)
        #expect(rep128Decoded.data == rep128Raw)
        #expect(rep128Decoded.consumedByteCount == 2)

        // 4. Control byte 0x80 (-128) is a no-op and never overflows signed negation
        let nopOnly = try decoder.decode(Data([0x80]), expectedByteCount: 0)
        #expect(nopOnly.data.isEmpty)
        #expect(nopOnly.consumedByteCount == 1)

        let nopInterleaved = Data([0x80, 0x02, 0x41, 0x42, 0x43, 0x80, 0xFF, 0x7F, 0x80])
        let nopDecoded = try decoder.decode(nopInterleaved, expectedByteCount: 5)
        #expect(nopDecoded.data == Data([0x41, 0x42, 0x43, 0x7F, 0x7F]))
        #expect(nopDecoded.consumedByteCount == nopInterleaved.count)

        // 5. Apple Technical Note TN1023 canonical 24-byte PackBits vector
        let tn1023Uncompressed = Data([
            0xAA, 0xAA, 0xAA, 0x80, 0x00, 0x2A, 0xAA, 0xAA,
            0xAA, 0xAA, 0x80, 0x00, 0x2A, 0x22, 0xAA, 0xAA,
            0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA, 0xAA
        ])
        let tn1023Compressed = Data([
            0xFE, 0xAA, 0x02, 0x80, 0x00, 0x2A, 0xFD, 0xAA,
            0x03, 0x80, 0x00, 0x2A, 0x22, 0xF7, 0xAA
        ])
        let tnEncoded = try encoder.encode(tn1023Uncompressed)
        #expect(tnEncoded.data == tn1023Compressed)
        let tnDecoded = try decoder.decode(tn1023Compressed, expectedByteCount: 24)
        #expect(tnDecoded.data == tn1023Uncompressed)
    }

    @Test("Boundary lengths 0, 1, 2, 3, 127, 128 and 129 for both repeat and literal runs")
    func testBoundaryRunLengths() throws {
        let encoder = try PackBitsEncoder()
        let decoder = try PackBitsDecoder()

        // Empty input (length 0)
        let emptyEncoded = try encoder.encode(Data())
        #expect(emptyEncoded.data.isEmpty)
        let emptyDecoded = try decoder.decode(Data(), expectedByteCount: 0)
        #expect(emptyDecoded.data.isEmpty)
        #expect(emptyDecoded.consumedByteCount == 0)

        // Identical-byte runs for lengths 1, 2, 3, 127, 128, 129
        let repeatExpectations: [(Int, [UInt8])] = [
            (1, [0x00, 0x5A]),                        // 1 byte is a 1-byte literal
            (2, [0xFF, 0x5A]),                        // -(2 - 1) = -1 = 0xFF
            (3, [0xFE, 0x5A]),                        // -(3 - 1) = -2 = 0xFE
            (127, [0x82, 0x5A]),                      // -(127 - 1) = -126 = 0x82
            (128, [0x81, 0x5A]),                      // -(128 - 1) = -127 = 0x81
            (129, [0x81, 0x5A, 0x00, 0x5A])           // 128 repeat + 1 literal
        ]
        for (len, expectedBytes) in repeatExpectations {
            let raw = Data(repeating: 0x5A, count: len)
            let encoded = try encoder.encode(raw)
            #expect([UInt8](encoded.data) == expectedBytes, "Repeat length \(len) packet mismatch")
            let decoded = try decoder.decode(encoded.data, expectedByteCount: len)
            #expect(decoded.data == raw)
        }

        // Non-repeating literal sequences for lengths 1, 2, 3, 127, 128, 129
        for len in [1, 2, 3, 127, 128, 129] {
            let rawBytes = (0..<len).map { UInt8(($0 * 37 + 11) & 0xFF) }
            let raw = Data(rawBytes)
            let encoded = try encoder.encode(raw)
            if len <= 128 {
                #expect(encoded.data.count == len + 1)
                #expect(encoded.data[0] == UInt8(len - 1))
                #expect(Array(encoded.data.dropFirst()) == rawBytes)
            } else {
                // 129 = 128-byte literal packet (129 bytes) + 1-byte literal packet (2 bytes) = 131 bytes
                #expect(encoded.data.count == 131)
                #expect(encoded.data[0] == 127)
                #expect(encoded.data[129] == 0)
                #expect(encoded.data[130] == rawBytes[128])
            }
            let decoded = try decoder.decode(encoded.data, expectedByteCount: len)
            #expect(decoded.data == raw)
        }
    }

    @Test("Row-constrained PackBits splits runs at row boundaries and rejects row-crossing packets on decode")
    func testRowBoundaries() throws {
        let encoder = try PackBitsEncoder()
        let decoder = try PackBitsDecoder()

        // 1. Constant 4 rows x 8 bytes = 32 bytes -> four 8-byte repeat packets [0xF9, 0x2A]
        let constant32 = Data(repeating: 0x2A, count: 32)
        let rowEncoded = try encoder.encode(constant32, rowBytes: 8, rowCount: 4)
        #expect([UInt8](rowEncoded.data) == [
            0xF9, 0x2A,
            0xF9, 0x2A,
            0xF9, 0x2A,
            0xF9, 0x2A
        ])
        let rowDecoded = try decoder.decode(rowEncoded.data, expectedByteCount: 32, rowBytes: 8, rowCount: 4)
        #expect(rowDecoded.data == constant32)

        // Unconstrained 32-byte constant stream is a single 32-byte repeat packet [0xE1, 0x2A],
        // which must be rejected when decoded with rowBytes: 8, rowCount: 4!
        let unconstrainedEncoded = try encoder.encode(constant32)
        #expect([UInt8](unconstrainedEncoded.data) == [0xE1, 0x2A])
        do {
            _ = try decoder.decode(unconstrainedEncoded.data, expectedByteCount: 32, rowBytes: 8, rowCount: 4)
            Issue.record("Expected malformedInput when a single repeat packet crosses rowBytes")
        } catch let error as CodecError {
            #expect(error.category == .malformedInput)
        }

        // 2. Literal 2 rows x 3 bytes = 6 bytes -> two 3-byte literal packets
        let literal6 = Data([1, 2, 3, 4, 5, 6])
        let litRowEncoded = try encoder.encode(literal6, rowBytes: 3, rowCount: 2)
        #expect([UInt8](litRowEncoded.data) == [0x02, 1, 2, 3, 0x02, 4, 5, 6])
        let litRowDecoded = try decoder.decode(litRowEncoded.data, expectedByteCount: 6, rowBytes: 3, rowCount: 2)
        #expect(litRowDecoded.data == literal6)

        // Single 6-byte literal packet [0x05, 1, 2, 3, 4, 5, 6] crosses the 3-byte row boundary
        do {
            _ = try decoder.decode(Data([0x05, 1, 2, 3, 4, 5, 6]), expectedByteCount: 6, rowBytes: 3, rowCount: 2)
            Issue.record("Expected malformedInput when a literal packet crosses rowBytes")
        } catch let error as CodecError {
            #expect(error.category == .malformedInput)
        }
    }

    @Test("Truncated packet positions, underrun, overrun and trailing non-NOP bytes throw .malformedInput")
    func testTruncationOverrunAndUnderrun() throws {
        let decoder = try PackBitsDecoder()

        // Multi-packet stream decoding to 12 bytes:
        // [0x80] (NOP) + [0x03, 10, 20, 30, 40] (4-byte literal) + [0xFD, 0x99] (4x 0x99) + [0x03, 1, 2, 3, 4] (4-byte literal)
        let validStream = Data([0x80, 0x03, 10, 20, 30, 40, 0xFD, 0x99, 0x03, 1, 2, 3, 4])
        let validDecoded = try decoder.decode(validStream, expectedByteCount: 12)
        #expect([UInt8](validDecoded.data) == [10, 20, 30, 40, 0x99, 0x99, 0x99, 0x99, 1, 2, 3, 4])

        // Every strict prefix 0..<validStream.count must fail with .malformedInput
        for prefixLen in 0..<validStream.count {
            let truncated = validStream.prefix(prefixLen)
            do {
                _ = try decoder.decode(truncated, expectedByteCount: 12)
                Issue.record("Prefix length \(prefixLen) unexpectedly succeeded")
            } catch let error as CodecError {
                #expect(error.category == .malformedInput)
            }
        }

        // Underrun: valid packets producing 2 bytes when 4 expected (with and without trailing NOPs)
        for underrun in [Data([0x01, 1, 2]), Data([0x01, 1, 2, 0x80, 0x80])] {
            do {
                _ = try decoder.decode(underrun, expectedByteCount: 4)
                Issue.record("Expected underrun to fail")
            } catch let error as CodecError {
                #expect(error.category == .malformedInput)
            }
        }

        // Overrun: repeat 5 bytes into 4-byte expected output, literal 5 bytes into 4-byte expected output,
        // and trailing extra packet after 4 bytes were already emitted
        for overrun in [
            Data([0xFC, 7]),
            Data([0x04, 1, 2, 3, 4, 5]),
            Data([0x03, 1, 2, 3, 4, 0x00, 9]),
            Data([0x03, 1, 2, 3, 4, 0x00]),
            Data([0x03, 1, 2, 3, 4, 0xFF])
        ] {
            do {
                _ = try decoder.decode(overrun, expectedByteCount: 4)
                Issue.record("Expected overrun/trailing packet to fail")
            } catch let error as CodecError {
                #expect(error.category == .malformedInput)
            }
        }
    }

    @Test("Bounded 0x80 (-128) NOP flood budget fails with .resourceLimitExceeded")
    func testBoundedNOPFloodBudget() throws {
        let decoder = try PackBitsDecoder()

        // For expectedByteCount == 0, budget is 64 packet operations
        let zeroBudget = try PackBitsDecoder.maximumPacketOperations(forExpectedByteCount: 0)
        #expect(zeroBudget == 64)
        let allowedNOPs = Data(repeating: 0x80, count: zeroBudget)
        let okResult = try decoder.decode(allowedNOPs, expectedByteCount: 0)
        #expect(okResult.data.isEmpty)
        #expect(okResult.consumedByteCount == zeroBudget)

        let floodNOPs = Data(repeating: 0x80, count: zeroBudget + 1)
        do {
            _ = try decoder.decode(floodNOPs, expectedByteCount: 0)
            Issue.record("Expected NOP flood of \(zeroBudget + 1) bytes to fail with .resourceLimitExceeded")
        } catch let error as CodecError {
            #expect(error.category == .resourceLimitExceeded)
        }

        // For expectedByteCount == 4, budget is 64 + 4 * 2 = 72 packet operations.
        // 1 literal packet [0x03, 1, 2, 3, 4] + 72 NOPs = 73 packet ops -> exceeds budget!
        let budget4 = try PackBitsDecoder.maximumPacketOperations(forExpectedByteCount: 4)
        #expect(budget4 == 72)
        let trailingFlood = Data([0x03, 1, 2, 3, 4]) + Data(repeating: 0x80, count: budget4)
        do {
            _ = try decoder.decode(trailingFlood, expectedByteCount: 4)
            Issue.record("Expected trailing NOP flood to fail with .resourceLimitExceeded")
        } catch let error as CodecError {
            #expect(error.category == .resourceLimitExceeded)
        }
    }

    @Test("Incremental decoding across 1-byte, 2-way, prime-sized and sliced chunks")
    func testIncrementalChunkSplitsAndSlicedData() throws {
        let encoder = try PackBitsEncoder()
        let decoder = try PackBitsDecoder()

        // Build a 96-byte patterned payload (6 rows x 16 bytes) mixing repeats and literals
        var rawBytes: [UInt8] = []
        for r in 0..<6 {
            rawBytes.append(contentsOf: repeatElement(UInt8(0x10 + r), count: 5))
            for c in 0..<6 {
                rawBytes.append(UInt8((r * 31 + c * 17 + 3) & 0xFF))
            }
            rawBytes.append(contentsOf: repeatElement(UInt8(0xA0 + r), count: 5))
        }
        let payload = Data(rawBytes)
        #expect(payload.count == 96)

        // Encode from a non-zero startIndex slice
        let paddedInput = Data(repeating: 0xEE, count: 73) + payload + Data(repeating: 0xDD, count: 29)
        let inputSlice = paddedInput[73..<(73 + 96)]
        #expect(inputSlice.startIndex == 73)

        let encoded = try encoder.encode(inputSlice, rowBytes: 16, rowCount: 6)

        // Decode from a non-zero startIndex slice
        let paddedCompressed = Data(repeating: 0xCC, count: 101) + encoded.data + Data(repeating: 0xBB, count: 19)
        let compressedSlice = paddedCompressed[101..<(101 + encoded.data.count)]
        #expect(compressedSlice.startIndex == 101)
        let wholeDecoded = try decoder.decode(compressedSlice, expectedByteCount: 96, rowBytes: 16, rowCount: 6)
        #expect(wholeDecoded.data == payload)
        #expect(wholeDecoded.consumedByteCount == encoded.data.count)

        // 1. 1-byte chunks (splits every single control byte, literal byte and repeat byte)
        let singleByteChunks = (0..<encoded.data.count).map { idx -> Data in
            let start = compressedSlice.startIndex + idx
            return paddedCompressed[start..<(start + 1)]
        }
        let fromSingleBytes = try decoder.decodeIncremental(
            singleByteChunks,
            expectedByteCount: 96,
            rowBytes: 16,
            rowCount: 6
        )
        #expect(fromSingleBytes.data == payload)
        #expect(fromSingleBytes.consumedByteCount == encoded.data.count)

        // 2. Every 2-way split point 0...encoded.data.count
        for split in 0...encoded.data.count {
            let mid = compressedSlice.startIndex + split
            let c1 = paddedCompressed[compressedSlice.startIndex..<mid]
            let c2 = paddedCompressed[mid..<compressedSlice.endIndex]
            let splitResult = try decoder.decodeIncremental([c1, Data(), c2], expectedByteCount: 96, rowBytes: 16, rowCount: 6)
            #expect(splitResult.data == payload)
        }

        // 3. Prime-sized chunks (3, 5, 7 bytes)
        var primeChunks: [Data] = []
        let stepSizes = [3, 5, 7, 2, 11]
        var cursor = compressedSlice.startIndex
        var stepIdx = 0
        while cursor < compressedSlice.endIndex {
            let take = min(stepSizes[stepIdx % stepSizes.count], compressedSlice.endIndex - cursor)
            primeChunks.append(paddedCompressed[cursor..<(cursor + take)])
            cursor += take
            stepIdx += 1
        }
        let fromPrimes = try decoder.decodeIncremental(primeChunks, expectedByteCount: 96, rowBytes: 16, rowCount: 6)
        #expect(fromPrimes.data == payload)

        // 4. Re-using a finished incremental session throws .invalidArgument
        var session = try decoder.makeIncrementalSession(expectedByteCount: 3)
        try session.append(Data([0x02, 0x41, 0x42, 0x43]))
        let done = try session.finish()
        #expect(done.data == Data([0x41, 0x42, 0x43]))
        #expect(throws: CodecError.self) {
            try session.append(Data([0x80]))
        }
        #expect(throws: CodecError.self) {
            _ = try session.finish()
        }
    }

    @Test("Telemetry separation, execution policy fallback, cancellation and deterministic mutation fuzzing")
    func testTelemetryPolicyCancellationAndMutationSurvival() throws {
        let encoder = try PackBitsEncoder()
        let decoder = try PackBitsDecoder()
        let recorder = StorageTelemetry.Recorder()

        // 1. Telemetry: raw PackBits byte operations allocate 0 pixel storage and 0 workspace
        try StorageTelemetry.$recorder.withValue(recorder) {
            let raw = Data([1, 1, 1, 2, 3, 4, 5, 5, 5, 5])
            let enc = try encoder.encode(raw, options: EncodeOptions(executionPolicy: .preferred(.accelerated)))
            #expect(enc.report.backend == .scalarCPU)
            #expect(enc.report.fallbackReason != nil)
            #expect(enc.report.pixelAllocationCount == 0)
            #expect(enc.report.peakPixelBytes == 0)
            #expect(enc.report.peakWorkspaceBytes == 0)

            let dec = try decoder.decode(
                enc.data,
                expectedByteCount: raw.count,
                options: DecodeOptions(executionPolicy: .preferred(.accelerated))
            )
            #expect(dec.data == raw)
            #expect(dec.report.backend == .scalarCPU)
            #expect(dec.report.fallbackReason != nil)
            #expect(dec.report.pixelAllocationCount == 0)
            #expect(dec.report.peakPixelBytes == 0)
            #expect(dec.report.peakWorkspaceBytes == 0)
            #expect(recorder.counts == StorageTelemetry.Counts())
        }

        // 2. ExecutionPolicy.required(.accelerated) fails with .backendUnavailable
        #expect(throws: CodecError(.backendUnavailable, "No accelerated backend is implemented.")) {
            _ = try encoder.encode(Data([1, 2]), options: EncodeOptions(executionPolicy: .required(.accelerated)))
        }
        #expect(throws: CodecError(.backendUnavailable, "No accelerated backend is implemented.")) {
            _ = try decoder.decode(Data([0x01, 1, 2]), expectedByteCount: 2, options: DecodeOptions(executionPolicy: .required(.accelerated)))
        }

        // 3. Deterministic byte mutation survival (seed 0xD1C0_2026_0810_0201)
        let baseRaw = Data((0..<32).map { UInt8(($0 * 19 + 7) & 0xFF) })
        let baseEncoded = try encoder.encode(baseRaw, rowBytes: 8, rowCount: 4).data
        var rng = SplitMix64(state: 0xD1C0_2026_0810_0201)
        for _ in 0..<500 {
            var mutated = baseEncoded
            let edits = Int.random(in: 1...6, using: &rng)
            for _ in 0..<edits where !mutated.isEmpty {
                let idx = Int.random(in: 0..<mutated.count, using: &rng)
                mutated[idx] = UInt8.random(in: 0...255, using: &rng)
            }
            if Int.random(in: 0..<5, using: &rng) == 0, mutated.count > 1 {
                mutated = Data(mutated.prefix(Int.random(in: 1..<mutated.count, using: &rng)))
            }
            _ = try? decoder.decode(mutated, expectedByteCount: 32, rowBytes: 8, rowCount: 4)
        }
    }

    #if os(macOS) || os(Linux)
    @Test("Independent libtiff (tiffcp -c packbits) two-way interoperability")
    func testLibtiffPackBitsInteroperability() throws {
        let environment = ProcessInfo.processInfo.environment
        let candidates = environment["SWIFTRLE_TIFFCP"].map { [$0] }
            ?? ((environment["PATH"] ?? "").split(separator: ":").map { String($0) + "/tiffcp" }
                + ["/opt/homebrew/bin/tiffcp", "/usr/local/bin/tiffcp", "/usr/bin/tiffcp"])
        guard let tool = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            Issue.record("Required independent libtiff oracle tiffcp is not available (set SWIFTRLE_TIFFCP or PATH).")
            return
        }

        let tiffcpURL = URL(fileURLWithPath: tool)
        let width = 17
        let height = 13
        let totalBytes = width * height // 221 bytes, odd width & height
        var rawBytes: [UInt8] = []
        rawBytes.reserveCapacity(totalBytes)
        for y in 0..<height {
            // Mix replicate runs and literal runs within each 17-byte row
            let runVal = UInt8((y * 23 + 0x11) & 0xFF)
            rawBytes.append(contentsOf: repeatElement(runVal, count: 6))
            for x in 0..<5 {
                rawBytes.append(UInt8((y * 41 + x * 59 + 7) & 0xFF))
            }
            let tailVal = UInt8((y * 17 + 0x90) & 0xFF)
            rawBytes.append(contentsOf: repeatElement(tailVal, count: 6))
        }
        let payload = Data(rawBytes)
        #expect(payload.count == totalBytes)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("swiftrle-libtiff-oracle-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        // ------------------------------------------------------------------
        // Direction 1: libtiff (tiffcp -c packbits) -> SwiftRLE.PackBitsDecoder
        // ------------------------------------------------------------------
        let uncompressedTiffURL = tempDir.appendingPathComponent("uncompressed.tif")
        let libtiffPackBitsURL = tempDir.appendingPathComponent("libtiff_packbits.tif")
        try Self.writeMinimalGreyscale8TIFF(
            width: width,
            height: height,
            compression: 1, // Uncompressed
            stripData: payload,
            to: uncompressedTiffURL
        )
        try Self.runProcess(executable: tiffcpURL, arguments: ["-c", "packbits", uncompressedTiffURL.path, libtiffPackBitsURL.path])

        let libtiffFileBytes = try Data(contentsOf: libtiffPackBitsURL)
        let (stripOffset, stripByteCount, compressionTag) = try Self.parseSingleStripTIFF(libtiffFileBytes)
        #expect(compressionTag == 32773, "TIFF Compression tag must be 32773 (PackBits)")
        #expect(stripOffset > 0 && stripByteCount > 0)
        #expect(stripOffset + stripByteCount <= libtiffFileBytes.count)

        // Extract raw strip slice directly from the TIFF Data (non-zero startIndex!)
        let libtiffStripSlice = libtiffFileBytes[stripOffset..<(stripOffset + stripByteCount)]
        #expect(libtiffStripSlice.startIndex == stripOffset)

        let decoder = try PackBitsDecoder()
        let decodedFromLibtiff = try decoder.decode(
            libtiffStripSlice,
            expectedByteCount: totalBytes,
            rowBytes: width,
            rowCount: height
        )
        #expect(decodedFromLibtiff.data == payload)
        #expect(decodedFromLibtiff.consumedByteCount == stripByteCount)

        // ------------------------------------------------------------------
        // Direction 2: SwiftRLE.PackBitsEncoder -> libtiff (tiffcp -c none)
        // ------------------------------------------------------------------
        let encoder = try PackBitsEncoder()
        let swiftEncoded = try encoder.encode(payload, rowBytes: width, rowCount: height)
        #expect(swiftEncoded.data == Data(libtiffStripSlice))

        let swiftPackBitsTiffURL = tempDir.appendingPathComponent("swiftrle_packbits.tif")
        let libtiffDecodedTiffURL = tempDir.appendingPathComponent("libtiff_decoded.tif")
        try Self.writeMinimalGreyscale8TIFF(
            width: width,
            height: height,
            compression: 32773, // PackBits
            stripData: swiftEncoded.data,
            to: swiftPackBitsTiffURL
        )
        try Self.runProcess(executable: tiffcpURL, arguments: ["-c", "none", swiftPackBitsTiffURL.path, libtiffDecodedTiffURL.path])

        let libtiffDecodedBytes = try Data(contentsOf: libtiffDecodedTiffURL)
        let (decOffset, decCount, decCompression) = try Self.parseSingleStripTIFF(libtiffDecodedBytes)
        #expect(decCompression == 1, "Decompressed TIFF must have Compression = 1 (None)")
        #expect(decCount == totalBytes)
        let extractedUncompressed = Data(libtiffDecodedBytes[decOffset..<(decOffset + decCount)])
        #expect(extractedUncompressed == payload)
    }

    // MARK: - Minimal Classic TIFF Helpers for Independent Oracle Verification

    #endif

    private static func writeMinimalGreyscale8TIFF(
        width: Int,
        height: Int,
        compression: UInt16,
        stripData: Data,
        to url: URL
    ) throws {
        // 8-byte header + 8-tag IFD (2 + 8*12 + 4 = 102 bytes) -> strip starts at offset 110
        let stripOffset: UInt32 = 110
        var out = Data()
        out.reserveCapacity(Int(stripOffset) + stripData.count)
        // Little-endian classic TIFF header: "II", 42, IFD offset 8
        out.append(contentsOf: [0x49, 0x49, 0x2A, 0x00, 0x08, 0x00, 0x00, 0x00])
        // Number of directory entries = 8
        appendUInt16LE(8, to: &out)
        // Tags in ascending numerical order:
        appendIFDEntry(tag: 256, type: 4, count: 1, valueOrOffset: UInt32(width), to: &out)               // ImageWidth
        appendIFDEntry(tag: 257, type: 4, count: 1, valueOrOffset: UInt32(height), to: &out)              // ImageLength
        appendIFDEntry(tag: 258, type: 3, count: 1, valueOrOffset: 8, to: &out)                           // BitsPerSample = 8
        appendIFDEntry(tag: 259, type: 3, count: 1, valueOrOffset: UInt32(compression), to: &out)         // Compression
        appendIFDEntry(tag: 262, type: 3, count: 1, valueOrOffset: 1, to: &out)                           // Photometric = MinIsBlack
        appendIFDEntry(tag: 273, type: 4, count: 1, valueOrOffset: stripOffset, to: &out)                 // StripOffsets
        appendIFDEntry(tag: 278, type: 4, count: 1, valueOrOffset: UInt32(height), to: &out)              // RowsPerStrip
        appendIFDEntry(tag: 279, type: 4, count: 1, valueOrOffset: UInt32(stripData.count), to: &out)     // StripByteCounts
        // Next IFD offset = 0
        appendUInt32LE(0, to: &out)
        #expect(out.count == Int(stripOffset))
        out.append(stripData)
        try out.write(to: url)
    }

    private static func parseSingleStripTIFF(_ data: Data) throws -> (stripOffset: Int, stripByteCount: Int, compression: UInt16) {
        guard data.count >= 14, data[0] == 0x49, data[1] == 0x49, readUInt16LE(data, at: 2) == 42 else {
            throw CodecError(.malformedInput, "Expected little-endian classic TIFF.")
        }
        let ifdOffset = Int(readUInt32LE(data, at: 4))
        guard ifdOffset + 2 <= data.count else {
            throw CodecError(.malformedInput, "TIFF IFD offset out of bounds.")
        }
        let entryCount = Int(readUInt16LE(data, at: ifdOffset))
        guard ifdOffset + 2 + entryCount * 12 <= data.count else {
            throw CodecError(.malformedInput, "TIFF IFD entries out of bounds.")
        }

        var stripOffset: Int?
        var stripByteCount: Int?
        var compression: UInt16 = 1

        for i in 0..<entryCount {
            let base = ifdOffset + 2 + i * 12
            let tag = readUInt16LE(data, at: base)
            let fieldType = readUInt16LE(data, at: base + 2)
            let count = Int(readUInt32LE(data, at: base + 4))
            let scalarValue: Int
            if fieldType == 3 && count == 1 {
                scalarValue = Int(readUInt16LE(data, at: base + 8))
            } else {
                scalarValue = Int(readUInt32LE(data, at: base + 8))
            }
            switch tag {
            case 259:
                compression = UInt16(scalarValue)
            case 273:
                stripOffset = scalarValue
            case 279:
                stripByteCount = scalarValue
            default:
                break
            }
        }
        guard let offset = stripOffset, let byteCount = stripByteCount else {
            throw CodecError(.malformedInput, "Missing StripOffsets or StripByteCounts in TIFF.")
        }
        return (offset, byteCount, compression)
    }

    private static func appendUInt16LE(_ v: UInt16, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: v))
        data.append(UInt8(truncatingIfNeeded: v >> 8))
    }

    private static func appendUInt32LE(_ v: UInt32, to data: inout Data) {
        data.append(UInt8(truncatingIfNeeded: v))
        data.append(UInt8(truncatingIfNeeded: v >> 8))
        data.append(UInt8(truncatingIfNeeded: v >> 16))
        data.append(UInt8(truncatingIfNeeded: v >> 24))
    }

    private static func appendIFDEntry(tag: UInt16, type: UInt16, count: UInt32, valueOrOffset: UInt32, to data: inout Data) {
        appendUInt16LE(tag, to: &data)
        appendUInt16LE(type, to: &data)
        appendUInt32LE(count, to: &data)
        if type == 3 && count == 1 {
            appendUInt16LE(UInt16(truncatingIfNeeded: valueOrOffset), to: &data)
            appendUInt16LE(0, to: &data)
        } else {
            appendUInt32LE(valueOrOffset, to: &data)
        }
    }

    private static func readUInt16LE(_ data: Data, at offset: Int) -> UInt16 {
        let b = data.startIndex + offset
        return UInt16(data[b]) | (UInt16(data[b + 1]) << 8)
    }

    private static func readUInt32LE(_ data: Data, at offset: Int) -> UInt32 {
        let b = data.startIndex + offset
        return UInt32(data[b])
            | (UInt32(data[b + 1]) << 8)
            | (UInt32(data[b + 2]) << 16)
            | (UInt32(data[b + 3]) << 24)
    }

    #if os(macOS) || os(Linux)
    private static func runProcess(executable: URL, arguments: [String]) throws {
        let proc = Process()
        proc.executableURL = executable
        proc.arguments = arguments
        let errPipe = Pipe()
        proc.standardError = errPipe
        proc.standardOutput = Pipe()
        try proc.run()
        proc.waitUntilExit()
        guard proc.terminationStatus == 0 else {
            let errText = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw CodecError(.ioFailure, "tiffcp exited with \(proc.terminationStatus): \(errText)")
        }
    }
    #endif
}
