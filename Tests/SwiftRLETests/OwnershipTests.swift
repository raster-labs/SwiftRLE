// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftRLE

@Suite("OwnedImageStorage and ImageDestination Lifetime Tests")
struct OwnershipTests {

    @Test("Preflight decode rejection leaves caller ImageDestination reservation reusable")
    func testPreflightRejectionPreservesDestinationReservation() async throws {
        let desc = try ImageDescriptor.greyscale16(width: 3, height: 2, meaningfulBits: 12, rowBytes: 8)
        let destination = try ImageDestination.allocate(descriptor: desc)
        let expectedID = destination.storage.allocationID
        let decoder = try Decoder()

        // 1. Missing RLEFrameDescriptor fails preflight (.invalidArgument)
        do {
            _ = try await decoder.decode(Data(repeating: 0, count: 64), into: destination)
            Issue.record("Expected invalidArgument when RLEFrameDescriptor is absent")
        } catch let error as CodecError {
            #expect(error.category == .invalidArgument)
        }

        // 2. Mismatched RLEFrameDescriptor fails preflight (.incompatibleImageLayout)
        let wrongFrameDesc = try RLEFrameDescriptor.greyscale16(width: 4, height: 2, meaningfulBits: 12)
        do {
            _ = try decoder.decodeSynchronously(
                Data(repeating: 0, count: 64),
                into: destination,
                options: DecodeOptions(codecOptions: try CodecOptions(frameDescriptor: wrongFrameDesc))
            )
            Issue.record("Expected incompatibleImageLayout for mismatched descriptor")
        } catch let error as CodecError {
            #expect(error.category == .incompatibleImageLayout)
        }

        // 3. Invalid header with valid descriptor fails preflight (.malformedInput) without beginning write
        let matchingFrameDesc = try RLEFrameDescriptor(imageDescriptor: desc)
        do {
            _ = try await decoder.decode(
                Data(repeating: 0, count: 64),
                into: destination,
                options: DecodeOptions(codecOptions: try CodecOptions(frameDescriptor: matchingFrameDesc))
            )
            Issue.record("Expected malformedInput for invalid header")
        } catch let error as CodecError {
            #expect(error.category == .malformedInput)
        }

        // Destination must still be writable and sealable with the original allocationID!
        let image = try destination.writeUInt16 { x, y in UInt16(x == 0 ? 4095 : y * 3 + x) }
        #expect(image.storage.allocationID == expectedID)
        #expect(try image.sampleUInt16(x: 0, y: 1) == 4095)
        #expect(try image.sampleUInt16(x: 2, y: 1) == 5)
    }

    @Test("Begun-write failure and cancellation invalidate ImageDestination and prevent publication")
    func testBegunWriteFailureAndCancellationInvalidation() async throws {
        let desc = try ImageDescriptor.greyscale16(width: 3, height: 2, meaningfulBits: 12, rowBytes: 8)

        // 1. Thrown error inside writeUInt16 (sample > 4095 for 12-bit image) invalidates destination
        let dest1 = try ImageDestination.allocate(descriptor: desc)
        #expect(throws: CodecError.self) {
            _ = try dest1.writeUInt16 { x, y in
                if x == 1 && y == 1 { return 4096 } // exceeds 12-bit range
                return 100
            }
        }
        // Subsequent write attempt on dest1 or its storage must fail with .storageUnavailable
        do {
            _ = try dest1.writeUInt16 { _, _ in 0 }
            Issue.record("Expected storageUnavailable on invalidated destination")
        } catch let error as CodecError {
            #expect(error.category == .storageUnavailable)
        }
        do {
            _ = try dest1.storage.reserveWrite()
            Issue.record("Expected storageUnavailable on invalidated storage")
        } catch let error as CodecError {
            #expect(error.category == .storageUnavailable)
        }

        // 2. Task cancellation during write invalidates destination
        let dest2 = try ImageDestination.allocate(descriptor: desc)
        let cancelledTask = Task { () -> Image in
            withUnsafeCurrentTask { $0?.cancel() }
            return try dest2.writeUInt16 { _, _ in 42 }
        }
        await #expect(throws: CancellationError.self) {
            _ = try await cancelledTask.value
        }
        do {
            _ = try dest2.writeUInt16 { _, _ in 0 }
            Issue.record("Expected storageUnavailable after cancelled write")
        } catch let error as CodecError {
            #expect(error.category == .storageUnavailable)
        }

        // 3. Explicit invalidateAfterFailure() invalidates an unused destination after admission
        let dest3 = try ImageDestination.allocate(descriptor: desc)
        dest3.invalidateAfterFailure()
        do {
            _ = try dest3.writeUInt16 { _, _ in 0 }
            Issue.record("Expected storageUnavailable after invalidateAfterFailure()")
        } catch let error as CodecError {
            #expect(error.category == .storageUnavailable)
        }
    }

    @Test("Double writer, stale lease, foreign lease, reentrant borrow and active-borrow finish/abort discipline")
    func testStorageLeaseExclusivityAndBorrowDiscipline() throws {
        let storageA = try OwnedImageStorage(byteCount: 16)
        let storageB = try OwnedImageStorage(byteCount: 16)
        let leaseA = try storageA.reserveWrite()
        let leaseB = try storageB.reserveWrite()
        let forgedLease = StorageWriteLease()

        // 1. Double reservation on storageA fails
        do {
            _ = try storageA.reserveWrite()
            Issue.record("Expected double reserveWrite to fail")
        } catch let error as CodecError {
            #expect(error.category == .storageUnavailable)
        }

        // 2. Foreign and forged leases fail on mutable borrow, finishAndSeal, and abortAndInvalidate
        for badLease in [leaseB, forgedLease] {
            #expect(throws: CodecError(.storageUnavailable, "Write lease is stale, foreign or unavailable.")) {
                try storageA.withUnsafeMutableBytes(lease: badLease) { _ in }
            }
            #expect(throws: CodecError(.storageUnavailable, "Write lease is stale, foreign or unavailable.")) {
                _ = try storageA.finishAndSeal(lease: badLease)
            }
            #expect(throws: CodecError(.storageUnavailable, "Write lease is stale, foreign or unavailable.")) {
                try storageA.abortAndInvalidate(lease: badLease)
            }
        }

        // 3. Same-thread reentrant borrow, finishAndSeal, and abortAndInvalidate inside active borrow fail promptly
        try storageA.withUnsafeMutableBytes(lease: leaseA) { buffer in
            buffer[0] = 0x5A
            #expect(throws: CodecError(.storageUnavailable, "A storage borrow is already active.")) {
                try storageA.withUnsafeMutableBytes(lease: leaseA) { _ in }
            }
            #expect(throws: CodecError(.storageUnavailable, "A storage borrow is already active.")) {
                _ = try storageA.finishAndSeal(lease: leaseA)
            }
            #expect(throws: CodecError(.storageUnavailable, "A storage borrow is already active.")) {
                try storageA.abortAndInvalidate(lease: leaseA)
            }
        }

        // 4. Cross-thread concurrent borrow/finish/abort while a mutable borrow is active fails promptly
        let enteredBorrow = DispatchSemaphore(value: 0)
        let releaseBorrow = DispatchSemaphore(value: 0)
        let exitedBorrow = DispatchSemaphore(value: 0)
        Thread.detachNewThread {
            try? storageA.withUnsafeMutableBytes(lease: leaseA) { _ in
                enteredBorrow.signal()
                releaseBorrow.wait()
            }
            exitedBorrow.signal()
        }
        enteredBorrow.wait()
        #expect(throws: CodecError(.storageUnavailable, "A storage borrow is already active.")) {
            try storageA.withUnsafeMutableBytes(lease: leaseA) { _ in }
        }
        #expect(throws: CodecError(.storageUnavailable, "A storage borrow is already active.")) {
            _ = try storageA.finishAndSeal(lease: leaseA)
        }
        #expect(throws: CodecError(.storageUnavailable, "A storage borrow is already active.")) {
            try storageA.abortAndInvalidate(lease: leaseA)
        }
        releaseBorrow.signal()
        exitedBorrow.wait()

        // 5. After finishAndSeal, leaseA becomes stale and cannot mutate, re-seal, or abort
        let sealed = try storageA.finishAndSeal(lease: leaseA)
        #expect(sealed.allocationID == storageA.allocationID)
        #expect(throws: CodecError.self) {
            try storageA.withUnsafeMutableBytes(lease: leaseA) { _ in }
        }
        #expect(throws: CodecError.self) {
            _ = try storageA.finishAndSeal(lease: leaseA)
        }
        #expect(throws: CodecError.self) {
            try storageA.abortAndInvalidate(lease: leaseA)
        }

        // Clean up storageB
        try storageB.abortAndInvalidate(lease: leaseB)
    }

    @Test("Concurrent sealed readers and single final allocation release")
    func testConcurrentReadersAndSingleFinalRelease() async throws {
        let recorder = StorageTelemetry.Recorder()
        try await StorageTelemetry.$recorder.withValue(recorder) {
            let desc = try ImageDescriptor.greyscale16(width: 5, height: 3, meaningfulBits: 12, rowBytes: 12, offset: 4)
            let expectedBytes = desc.requiredByteCount
            var allocationID: UUID?

            do {
                let destination = try ImageDestination.allocate(descriptor: desc)
                allocationID = destination.storage.allocationID
                #expect(recorder.counts.pixelAllocations == 1)
                #expect(recorder.counts.pixelBytes == expectedBytes)
                #expect(recorder.counts.pixelReleases == 0)

                let image = try destination.writeUInt16 { x, y in
                    UInt16((x * 13 + y * 29) & 0x0FFF)
                }
                #expect(image.storage.allocationID == allocationID)
                // Sealing transfers ownership without a second allocation or premature release
                #expect(recorder.counts.pixelAllocations == 1)
                #expect(recorder.counts.pixelReleases == 0)

                // 8 concurrent readers share the sealed allocation simultaneously
                try await withThrowingTaskGroup(of: [UInt16].self) { group in
                    for _ in 0..<8 {
                        group.addTask {
                            var values: [UInt16] = []
                            values.reserveCapacity(15)
                            for y in 0..<desc.height {
                                for x in 0..<desc.width {
                                    values.append(try image.sampleUInt16(x: x, y: y))
                                }
                            }
                            return values
                        }
                    }
                    var reference: [UInt16]?
                    for try await result in group {
                        if let ref = reference {
                            #expect(result == ref)
                        } else {
                            reference = result
                        }
                    }
                }
                #expect(recorder.counts.pixelReleases == 0)
            }

            // Once `destination` and `image` leave scope after all readers finish,
            // the underlying allocation is released exactly once.
            #expect(recorder.counts.pixelAllocations == 1)
            #expect(recorder.counts.pixelReleases == 1)
            #expect(recorder.counts.pixelReleasedBytes == expectedBytes)
        }
    }

    @Test("Abandoned unsealed ImageDestination releases its allocation exactly once")
    func testAbandonedDestinationSingleRelease() throws {
        let recorder = StorageTelemetry.Recorder()
        try StorageTelemetry.$recorder.withValue(recorder) {
            let desc = try ImageDescriptor.greyscale16(width: 4, height: 2)
            do {
                let destination = try ImageDestination.allocate(descriptor: desc)
                _ = destination.storage.allocationID
                #expect(recorder.counts.pixelAllocations == 1)
                #expect(recorder.counts.pixelReleases == 0)
            }
            #expect(recorder.counts.pixelAllocations == 1)
            #expect(recorder.counts.pixelReleases == 1)
        }
    }
}
