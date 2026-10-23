// SPDX-License-Identifier: Apache-2.0
import Synchronization

/// Counters of the allocations this module makes for pixels and algorithm
/// workspace, so that a shared-storage claim can be checked against
/// instrumentation rather than address equality alone (MEM-13). A test binds
/// a `Recorder` to the current task; every allocation made by that task or
/// its children is counted there. Without a recorder nothing is recorded.
/// Counters hold sizes only, never contents or addresses.
struct StorageTelemetry: Sendable {
    struct Counts: Sendable, Equatable {
        var pixelAllocations = 0
        var pixelBytes = 0
        var pixelReleases = 0
        var pixelReleasedBytes = 0
        var workspaceAllocations = 0
        var workspaceBytes = 0
        var copyEvents = 0
        var copyBytes = 0
    }

    final class Recorder: Sendable {
        private let state = Mutex(Counts())
        init() {}
        var counts: Counts { state.withLock { $0 } }
        func reset() { state.withLock { $0 = Counts() } }
        fileprivate func add(_ body: (inout Counts) -> Void) { state.withLock { body(&$0) } }
    }

    @TaskLocal static var recorder: Recorder?

    /// An `OwnedImageStorage` allocation: the only pixel allocation this module makes.
    static func recordPixelAllocation(bytes: Int) {
        recorder?.add { $0.pixelAllocations += 1; $0.pixelBytes += bytes }
    }

    /// Final release of an `OwnedImageStorage` allocation (after sealing and last reader exit, or abort/deinit).
    static func recordPixelRelease(bytes: Int) {
        recorder?.add { $0.pixelReleases += 1; $0.pixelReleasedBytes += bytes }
    }

    /// A codec workspace allocation (row/packet workspace).
    static func recordWorkspaceAllocation(bytes: Int) {
        recorder?.add { $0.workspaceAllocations += 1; $0.workspaceBytes += bytes }
    }

    /// A value-preserving layout conversion copy when `CopyPolicy.allowCopy` is used.
    static func recordCopyEvent(bytes: Int) {
        recorder?.add { $0.copyEvents += 1; $0.copyBytes += bytes }
    }
}

/// Test-only mutations of the shared-storage path (TESTING TEST-09). A
/// mutation that changes nothing would show the evidence is decorative, so a
/// test binds one to its task, counts the expectations that fail, and lets the
/// binding end. The value is task-local: it cannot leak into other operations,
/// and no public option selects it.
enum SharedPathMutation: Sendable, Equatable {
    case none
    /// Write and read samples packed, ignoring the caller's row stride.
    case ignoreRowStride
    /// Use the opposite byte order from the descriptor.
    case wrongByteOrder

    @TaskLocal static var active: SharedPathMutation = .none
}
