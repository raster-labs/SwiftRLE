// SPDX-License-Identifier: MIT
import Dispatch
import Foundation
import Synchronization

/// Narrow raw pointer wrapper used strictly within synchronous scoped borrows (`withUnsafeBytes`)
/// where parallel workers read from immutable memory.
internal struct UnsafeSendableRawPointer: @unchecked Sendable {
    internal let baseAddress: UnsafeRawPointer
    internal let count: Int

    @inline(__always)
    internal init(baseAddress: UnsafeRawPointer, count: Int) {
        self.baseAddress = baseAddress
        self.count = count
    }
}

/// Narrow mutable raw pointer wrapper used strictly within synchronous scoped borrows
/// where each job writes to provably disjoint byte lanes or row ranges.
internal struct UnsafeSendableMutableRawPointer: @unchecked Sendable {
    internal let baseAddress: UnsafeMutableRawPointer
    internal let count: Int

    @inline(__always)
    internal init(baseAddress: UnsafeMutableRawPointer, count: Int) {
        self.baseAddress = baseAddress
        self.count = count
    }
}

/// Thread-safe error capture box retaining the earliest thrown error across parallel workers,
/// prioritizing `CancellationError` over downstream errors.
internal final class FirstErrorBox: Sendable {
    private let mutex = Mutex<(any Error)?>(nil)
    private let hasErrorFlag = Atomic<Bool>(false)

    internal init() {}

    @inline(__always)
    internal var hasError: Bool {
        hasErrorFlag.load(ordering: .relaxed)
    }

    internal func storeIfFirst(_ error: any Error) {
        mutex.withLock { slot in
            if slot == nil {
                slot = error
                hasErrorFlag.store(true, ordering: .releasing)
            } else if error is CancellationError, !(slot is CancellationError) {
                slot = error
            }
        }
    }

    internal func rethrowIfNeeded() throws {
        if hasErrorFlag.load(ordering: .acquiring) {
            let err = mutex.withLock { $0 }
            if let err {
                throw err
            }
        }
    }
}

/// Cooperative cancellation flag shared with GCD workers spawned inside an async `Task`.
internal final class OperationCancellationToken: Sendable {
    private let flag = Atomic<Bool>(false)

    internal init() {}

    @inline(__always)
    internal var isCancelled: Bool {
        flag.load(ordering: .relaxed)
    }

    internal func cancel() {
        flag.store(true, ordering: .releasing)
    }
}

/// Bounded work-stealing parallel executor honoring `ResourceLimits.maximumWorkers`.
internal enum BoundedParallelPool {
    @TaskLocal internal static var isInsideParallelRegion: Bool = false
    @TaskLocal internal static var activeCancellation: OperationCancellationToken? = nil

    internal static func withTaskCancellationBridge<T: Sendable>(
        _ body: @Sendable () throws -> T
    ) async throws -> T {
        let token = OperationCancellationToken()
        return try await withTaskCancellationHandler {
            try $activeCancellation.withValue(token) {
                try body()
            }
        } onCancel: {
            token.cancel()
        }
    }

    @inline(__always)
    internal static func checkCancellation() throws {
        try Task.checkCancellation()
        if activeCancellation?.isCancelled == true {
            throw CancellationError()
        }
    }

    private struct TaskLocalSnapshot: @unchecked Sendable {
        let forceUnavailable: Bool
        let storageRecorder: StorageTelemetry.Recorder?
        let sharedMutation: SharedPathMutation
        let cancellation: OperationCancellationToken?
        let hasOverrides: Bool

        @inline(__always)
        init() {
            self.forceUnavailable = AccelerationRuntime.forceUnavailable
            self.storageRecorder = StorageTelemetry.recorder
            self.sharedMutation = SharedPathMutation.active
            self.cancellation = BoundedParallelPool.activeCancellation
            self.hasOverrides = forceUnavailable || storageRecorder != nil || sharedMutation != .none || cancellation != nil
        }

        @inline(__always)
        func run(_ body: () -> Void) {
            if !hasOverrides {
                BoundedParallelPool.$isInsideParallelRegion.withValue(true, operation: body)
                return
            }
            BoundedParallelPool.$isInsideParallelRegion.withValue(true) {
                BoundedParallelPool.$activeCancellation.withValue(cancellation) {
                    AccelerationRuntime.$forceUnavailable.withValue(forceUnavailable) {
                        StorageTelemetry.$recorder.withValue(storageRecorder) {
                            SharedPathMutation.$active.withValue(sharedMutation, operation: body)
                        }
                    }
                }
            }
        }
    }

    @inline(__always)
    internal static func effectiveWorkers(requested: Int, jobCount: Int) -> Int {
        if isInsideParallelRegion || requested <= 1 || jobCount <= 1 {
            return 1
        }
        return min(requested, jobCount)
    }

    @inline(__always)
    internal static func forEach(
        jobCount: Int,
        maxWorkers: Int,
        body: @Sendable (_ jobIndex: Int) throws -> Void
    ) throws {
        try forEach(jobCount: jobCount, maxWorkers: maxWorkers) { jobIndex, _ in
            try body(jobIndex)
        }
    }

    internal static func forEach(
        jobCount: Int,
        maxWorkers: Int,
        body: @Sendable (_ jobIndex: Int, _ workerIndex: Int) throws -> Void
    ) throws {
        guard jobCount > 0 else { return }
        let workers = effectiveWorkers(requested: maxWorkers, jobCount: jobCount)
        if workers <= 1 {
            for index in 0..<jobCount {
                try checkCancellation()
                try body(index, 0)
            }
            return
        }

        try checkCancellation()
        let snapshot = TaskLocalSnapshot()
        let cursor = Atomic<Int>(0)
        let errorBox = FirstErrorBox()
        let cancelledFlag = Atomic<Bool>(false)

        DispatchQueue.concurrentPerform(iterations: workers) { workerIndex in
            if errorBox.hasError { return }
            snapshot.run {
                while !errorBox.hasError {
                    if Task.isCancelled
                        || snapshot.cancellation?.isCancelled == true
                        || cancelledFlag.load(ordering: .relaxed) {
                        cancelledFlag.store(true, ordering: .releasing)
                        errorBox.storeIfFirst(CancellationError())
                        break
                    }
                    let job = cursor.wrappingAdd(1, ordering: .relaxed).oldValue
                    if job >= jobCount { break }
                    do {
                        try body(job, workerIndex)
                    } catch {
                        if error is CancellationError {
                            cancelledFlag.store(true, ordering: .releasing)
                        }
                        errorBox.storeIfFirst(error)
                        break
                    }
                }
            }
        }

        try errorBox.rethrowIfNeeded()
        try checkCancellation()
    }
}
