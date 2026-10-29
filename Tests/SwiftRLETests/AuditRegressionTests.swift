// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
@testable import SwiftRLE

@Suite("R1 independent audit regressions")
struct AuditRegressionTests {
    private func rejects(_ category: CodecError.Category, _ body: () throws -> Void) {
        do { try body(); Issue.record("Expected rejection: \(category)") }
        catch let error as CodecError { #expect(error.category == category) }
        catch { Issue.record("Unexpected error: \(error)") }
    }

    @Test func deadlineConversionIsChecked() throws {
        for value in [1e20, Double.greatestFiniteMagnitude, .infinity, .nan, 0, -1] {
            rejects(.invalidArgument) { _ = try ResourceLimits(deadlineSeconds: value) }
        }
        let largest = try ResourceLimits(deadlineSeconds: Double(Int64.max / 1_000_000_000))
        #expect(try PackBitsEncoder().encode(Data(), options: .init(resourceLimits: largest)).data.isEmpty)
        #expect(try PackBitsDecoder().decode(Data(), expectedByteCount: 0, options: .init(resourceLimits: largest)).data.isEmpty)
    }

    @Test func aggregateMemoryAdmission() throws {
        let encoder = try PackBitsEncoder(), decoder = try PackBitsDecoder()
        let tooSmall = try ResourceLimits(maximumMemoryBytes: 128)
        let exact = try ResourceLimits(maximumMemoryBytes: 130)
        let raw = Data(repeating: 9, count: 128), encoded = Data([129, 9])
        rejects(.resourceLimitExceeded) { _ = try encoder.encode(raw, options: .init(resourceLimits: tooSmall)) }
        rejects(.resourceLimitExceeded) { _ = try decoder.decode(encoded, expectedByteCount: 128, options: .init(resourceLimits: tooSmall)) }
        rejects(.resourceLimitExceeded) { _ = try decoder.decodeIncremental([Data([129]), Data([9])], expectedByteCount: 128, options: .init(resourceLimits: tooSmall)) }
        #expect(try encoder.encode(raw, options: .init(resourceLimits: exact)).data == encoded)
        #expect(try decoder.decode(encoded, expectedByteCount: 128, options: .init(resourceLimits: exact)).data == raw)
        var session = try decoder.makeIncrementalSession(expectedByteCount: 128, options: .init(resourceLimits: tooSmall))
        rejects(.resourceLimitExceeded) { try session.append(encoded) }
        rejects(.invalidArgument) { _ = try session.finish() }
    }

    @Test func incrementalFailureIsTerminal() throws {
        let decoder = try PackBitsDecoder()
        for bad in [Data([0, 9, 0]), Data([0, 9, 255, 7]), Data([1, 9, 8])] {
            var session = try decoder.makeIncrementalSession(expectedByteCount: 1)
            rejects(.malformedInput) { try session.append(bad) }
            rejects(.invalidArgument) { try session.append(Data()) }
            rejects(.invalidArgument) { _ = try session.finish() }
        }
        var flood = try decoder.makeIncrementalSession(expectedByteCount: 0)
        rejects(.resourceLimitExceeded) { try flood.append(Data(repeating: 128, count: 65)) }
        rejects(.invalidArgument) { _ = try flood.finish() }
    }

    @Test func packetisationNeverExceedsPublishedBound() throws {
        let encoder = try PackBitsEncoder()
        let regression = Data([1, 2, 2, 3, 4, 4])
        #expect(try encoder.encode(regression).data.count == 8)
        #expect(try PackBitsEncoder.worstCaseEncodedByteCount(forByteCount: regression.count) >= 8)
        // Exhaustive short binary inputs catch fragmented literals and two-byte repeats.
        for length in 0...10 {
            let bound = try PackBitsEncoder.worstCaseEncodedByteCount(forByteCount: length)
            for bits in 0..<(1 << length) {
                let bytes = Data((0..<length).map { UInt8((bits >> $0) & 1) })
                #expect(try encoder.encode(bytes).data.count <= bound)
            }
        }
        for length in [127, 128, 129, 255, 256, 257] {
            let row: [UInt8] = (0..<length).map { index in
                let pair = (index / 3) * 2
                let offset = index % 3 == 0 ? 0 : 1
                return UInt8((pair + offset) % 251)
            }
            let bytes = Data(row + row)
            let bound = try PackBitsEncoder.worstCaseEncodedByteCount(forByteCount: bytes.count, rowBytes: length, rowCount: 2)
            #expect(try encoder.encode(bytes, rowBytes: length, rowCount: 2).data.count <= bound)
        }
        rejects(.invalidArgument) { _ = try PackBitsEncoder.worstCaseEncodedByteCount(forByteCount: Int.max) }
    }

    @Test func callbacksCannotHideExpiredDeadlines() throws {
        let limits = try ResourceLimits(deadlineSeconds: 0.001)
        rejects(.resourceLimitExceeded) {
            _ = try PackBitsEncoder().encode(Data(), options: .init(resourceLimits: limits, progress: { update in
                if update.phase == .inspecting { Thread.sleep(forTimeInterval: 0.01) }
            }))
        }
        rejects(.resourceLimitExceeded) {
            _ = try PackBitsDecoder().decode(Data(), expectedByteCount: 0, options: .init(resourceLimits: limits, progress: { update in
                if update.phase == .processing { Thread.sleep(forTimeInterval: 0.01) }
            }))
        }
    }

    @Test func cancellationDuringPackBitsWorkDoesNotPublish() async throws {
        let task = Task {
            try PackBitsEncoder().encode(Data(repeating: 1, count: 128), options: .init(progress: { update in
                if update.phase == .processing { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        let decode = Task {
            try PackBitsDecoder().decode(Data([129, 1]), expectedByteCount: 128, options: .init(progress: { update in
                if update.phase == .processing { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        await #expect(throws: CancellationError.self) { _ = try await decode.value }
    }

    @Test func terminalCompletedCallbackRechecksCancellation() async throws {
        let encodeTask = Task {
            try PackBitsEncoder().encode(Data([42, 42, 7]), options: .init(progress: { update in
                if update.phase == .completed { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        await #expect(throws: CancellationError.self) { _ = try await encodeTask.value }

        let syncEncodeTask = Task {
            try PackBitsEncoder().encodeSynchronously(Data([42]), options: .init(progress: { update in
                if update.phase == .completed { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        await #expect(throws: CancellationError.self) { _ = try await syncEncodeTask.value }

        let decodeTask = Task {
            try PackBitsDecoder().decode(Data([0, 42]), expectedByteCount: 1, options: .init(progress: { update in
                if update.phase == .completed { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        await #expect(throws: CancellationError.self) { _ = try await decodeTask.value }

        let incrementalCollectionTask = Task {
            try PackBitsDecoder().decodeIncremental([Data([0]), Data([42])], expectedByteCount: 1, options: .init(progress: { update in
                if update.phase == .completed { withUnsafeCurrentTask { $0?.cancel() } }
            }))
        }
        await #expect(throws: CancellationError.self) { _ = try await incrementalCollectionTask.value }

        let sessionTask = Task<PackBitsDecoder.IncrementalSession, any Error> {
            var session = try PackBitsDecoder().makeIncrementalSession(
                expectedByteCount: 2,
                options: .init(progress: { update in
                    if update.phase == .completed { withUnsafeCurrentTask { $0?.cancel() } }
                })
            )
            try session.append(Data([255, 9]))
            do {
                _ = try session.finish()
                Issue.record("Expected CancellationError from finish() after completed callback cancellation")
            } catch is CancellationError {
                // Expected; session failure must remain terminal even while task is cancelled.
            }
            rejects(.invalidArgument) { try session.append(Data()) }
            rejects(.invalidArgument) { _ = try session.finish() }
            return session
        }
        var closedSession = try await sessionTask.value
        rejects(.invalidArgument) { try closedSession.append(Data([0, 1])) }
        rejects(.invalidArgument) { _ = try closedSession.finish() }
    }

    @Test func terminalCompletedCallbackRechecksDeadlineAndKeepsSessionTerminal() throws {
        let limits = try ResourceLimits(deadlineSeconds: 0.01)

        rejects(.resourceLimitExceeded) {
            _ = try PackBitsEncoder().encode(Data([42]), options: .init(resourceLimits: limits, progress: { update in
                if update.phase == .completed { Thread.sleep(forTimeInterval: 0.03) }
            }))
        }

        rejects(.resourceLimitExceeded) {
            _ = try PackBitsDecoder().decode(Data([0, 42]), expectedByteCount: 1, options: .init(resourceLimits: limits, progress: { update in
                if update.phase == .completed { Thread.sleep(forTimeInterval: 0.03) }
            }))
        }

        rejects(.resourceLimitExceeded) {
            _ = try PackBitsDecoder().decodeIncremental([Data([0]), Data([42])], expectedByteCount: 1, options: .init(resourceLimits: limits, progress: { update in
                if update.phase == .completed { Thread.sleep(forTimeInterval: 0.03) }
            }))
        }

        var session = try PackBitsDecoder().makeIncrementalSession(
            expectedByteCount: 2,
            options: .init(resourceLimits: limits, progress: { update in
                if update.phase == .completed { Thread.sleep(forTimeInterval: 0.03) }
            })
        )
        try session.append(Data([255, 7]))
        rejects(.resourceLimitExceeded) { _ = try session.finish() }
        rejects(.invalidArgument) { try session.append(Data()) }
        rejects(.invalidArgument) { _ = try session.finish() }
    }

    @Test func callbackFreeAndHealthyCompletedCallbackSuccessUnchanged() throws {
        let encoder = try PackBitsEncoder(), decoder = try PackBitsDecoder()
        let raw = Data([1, 1, 1, 2, 3, 4, 4])

        let encodedNoCallback = try encoder.encode(raw)
        let decodedNoCallback = try decoder.decode(encodedNoCallback.data, expectedByteCount: raw.count)
        #expect(decodedNoCallback.data == raw)

        var withoutCallbackSession = try decoder.makeIncrementalSession(expectedByteCount: raw.count)
        try withoutCallbackSession.append(encodedNoCallback.data)
        #expect(try withoutCallbackSession.finish().data == raw)
        rejects(.invalidArgument) { _ = try withoutCallbackSession.finish() }

        let encodedWithCallback = try encoder.encode(raw, options: .init(progress: { _ in }))
        #expect(encodedWithCallback.data == encodedNoCallback.data)

        var withCallbackSession = try decoder.makeIncrementalSession(expectedByteCount: raw.count, options: .init(progress: { _ in }))
        for byte in encodedWithCallback.data {
            try withCallbackSession.append(Data([byte]))
        }
        #expect(try withCallbackSession.finish().data == raw)
    }
}
