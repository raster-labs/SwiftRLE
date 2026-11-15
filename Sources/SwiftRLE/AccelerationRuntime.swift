// SPDX-License-Identifier: MIT
import Foundation
import Synchronization

/// Runtime capability detection and `ExecutionPolicy` resolution for CPU SIMD + parallel RLE execution.
package enum AccelerationRuntime {
    /// Task-local override used by tests to deterministically exercise fallback and `.backendUnavailable`
    /// paths on hardware where CPU SIMD acceleration is available.
    @TaskLocal package static var forceUnavailable: Bool = false

    /// Whether CPU vector acceleration (ARM64 NEON / x86_64 SIMD / Accelerate) is compiled into this target.
    package static var hasHardwareSIMD: Bool {
        #if arch(arm64) || arch(x86_64) || canImport(Accelerate)
        return true
        #else
        return false
        #endif
    }

    /// Whether `.accelerated` execution is currently available on this runtime.
    package static var isAvailable: Bool {
        guard !forceUnavailable else { return false }
        return hasHardwareSIMD
    }

    /// Backends advertised by `Encoder.capabilities`, `Decoder.capabilities`, `PackBitsEncoder.capabilities`,
    /// and `PackBitsDecoder.capabilities`.
    package static var availableBackends: [Backend] {
        isAvailable ? [.scalarCPU, .accelerated] : [.scalarCPU]
    }

    package struct ResolvedExecution: Sendable, Equatable {
        package let backend: Backend
        package let fallbackReason: String?

        package init(backend: Backend, fallbackReason: String?) {
            self.backend = backend
            self.fallbackReason = fallbackReason
        }
    }

    package static func resolve(_ policy: ExecutionPolicy) throws -> ResolvedExecution {
        switch policy {
        case .scalarCPU, .preferred(.scalarCPU), .required(.scalarCPU):
            return ResolvedExecution(backend: .scalarCPU, fallbackReason: nil)
        case .automatic:
            if isAvailable {
                return ResolvedExecution(backend: .accelerated, fallbackReason: nil)
            }
            return ResolvedExecution(backend: .scalarCPU, fallbackReason: nil)
        case .preferred(.accelerated):
            if isAvailable {
                return ResolvedExecution(backend: .accelerated, fallbackReason: nil)
            }
            return ResolvedExecution(
                backend: .scalarCPU,
                fallbackReason: "Accelerated backend is unavailable on this runtime; using scalarCPU."
            )
        case .required(.accelerated):
            guard isAvailable else {
                throw CodecError(.backendUnavailable, "No accelerated backend is available on this runtime.")
            }
            return ResolvedExecution(backend: .accelerated, fallbackReason: nil)
        }
    }

    package static func withSimulatedUnavailable<R>(_ body: () throws -> R) rethrows -> R {
        try $forceUnavailable.withValue(true, operation: body)
    }

    package static func withSimulatedUnavailable<R>(_ body: () async throws -> R) async rethrows -> R {
        try await $forceUnavailable.withValue(true) {
            try await body()
        }
    }
}
