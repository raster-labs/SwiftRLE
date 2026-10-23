# Platform and build contract

Contract **0.7.0**. The table is intended support, not a claim of completed builds.

| Environment | Minimum / architecture | Validation responsibility |
| --- | --- | --- |
| macOS | 26.0; Apple arm64 primary | Full core, CLI, unit/regression, memory, performance and acceleration tests |
| macOS | 26.0; Intel x86_64 secondary | Native build/run and core/CLI correctness; isolated Intel support |
| iOS and iPadOS | 26.0; supported Apple devices and simulators | Library build, simulator tests and representative device tests |
| tvOS | 26.0; supported Apple devices and simulators | Library build and applicable runtime tests |
| visionOS | 26.0; supported Apple devices and simulators | Library build and applicable runtime tests |
| watchOS | 26.0; SDK-supported Watch architectures and simulators | Library build, bounded-memory runtime profile, cancellation/resource tests |
| Linux ARM64 | Ubuntu 24.04 reference distribution; AArch64 | Native build/run, scalar core, CLI and regression; optional ARM optimisation |
| Linux x86_64 | Ubuntu 24.04 reference distribution | Native build/run, scalar core, CLI and regression; isolated Intel optimisation |

**PLAT-01.** The manifest minimum is Swift 6.2, with Swift 6 language mode and complete concurrency checking throughout library, CLI and test targets. Swift 6.4 is the qualified primary toolchain: build and test on it, and pin its build identity in evidence. Both are supported compilers, and CI runs both, because a manifest minimum is a resolution floor rather than a statement of which toolchain is preferred. Raising the manifest floor strands every consumer on an older toolchain, so it requires its own contract change and a recorded consumer impact. Pin SDK/toolchain/container revisions in evidence. Use an Xcode supporting OS 26 SDKs. iPadOS uses the iOS SwiftPM deployment setting. Linux has its own distribution/runtime baseline; it has no Apple-style OS 26 floor. Ubuntu 24.04 is this foundation's concrete engineering baseline; wider distribution support needs evidence and a recorded expansion.

**PLAT-02.** The Apple deployment minimum is exactly 26.0 unless an approved contract change raises it. A deployment floor may only be raised against a released SDK with a generally available toolchain and a stable continuous-integration runner; a public preview or beta SDK is not sufficient evidence. Adopting an API that is unavailable below the floor is a reason to choose a different API, not a reason to raise the floor. An SDK update alone must not raise package minima. Do not assume watchOS shares every framework or architecture of macOS/iOS. Probe API availability per target. No 32-bit Intel or general Linux ARMv7 support is implied. Windows is outside the current scope.

## Compile-time segregation

**PLAT-03.** Separate common scalar algorithms from Apple framework integration, Linux integration, ARM-specific kernels and x86-specific kernels. Share OS-independent SIMD primitives where they genuinely apply to both operating systems. Keep macOS Intel and Linux Intel glue separately removable. Common scalar code remains available on Apple Silicon and must not be misclassified as legacy Intel code.

Use Swift target-platform and architecture compilation conditions and target/dependency selection to omit unavailable implementations, imports, native objects and resources. A folder name alone does not exclude code. A manifest is evaluated on the build host; do not use host OS/CPU detection to decide the target architecture during cross-compilation. Centralise selection and test target configurations. Match equivalent conditions at C/C++ boundaries if retained. Never select a backend using the machine's branding alone.

**PLAT-04.** An Apple arm64 product contains no Linux-only or x86-only implementation; Linux products contain no Apple-framework link requirements. A universal macOS artifact may intentionally contain separate arm64 and x86_64 slices. Validate each slice rather than calling the whole universal file ARM-only. Runtime capability dispatch is appropriate only among backends compiled for that target. Optional GPU/SIMD unavailability must not remove codec correctness.

**PLAT-05.** Ship a usable scalar path on every claimed environment. Apple Accelerate/Metal/Core Video adapters are optional and availability-guarded. Do not fall back to OS JPEG decoding on Apple while leaving the advertised Linux native decoder missing. Optional C/C++ kernels remain small, audited and compared with the scalar reference; no external codec runtime is permitted.

## Build and packaging acceptance

Milestone 1 establishes the standalone package and contract tests. Consult each repository's evidence for executed builds; this platform table remains the intended qualification matrix, not a declaration that every target has passed.

When implemented, validate a fresh URL-based consumer of each library, using a versioned prerelease when dependency resolution requires one. It must not discover sibling checkouts or require another suite package. Do not require manifest unsafe flags that make the package unusable as a dependency. Keep examples, benchmarks and CLI entry points out of library test linkage where they can hijack a test executable's main function.

For every target, retain exact build/test invocations, SDK version, target triple, host/device and outcome. Cross-compilation proves buildability, not runtime correctness. Rosetta/emulation is supplemental evidence, not a substitute for native Intel/Linux ARM runtime gates. If a required runner/device is unavailable, mark that gate unexecuted and do not publish support as verified. Do not silently reduce scope to the agent's local machine.

Initial CI should run complete core correctness on macOS arm64 and both Linux architectures, plus an Apple SDK build matrix. Add native macOS Intel and representative Apple runtime checks before the stable release claims those targets. Resource-limited Watch tests use their explicit profile; they must not be disabled merely to make the matrix green.

References: [Swift Linux toolchains](https://www.swift.org/install/linux/ubuntu/24_04/), [Xcode SDK compatibility](https://developer.apple.com/xcode/system-requirements), [Swift compilation conditions](https://github.com/swiftlang/swift-book/blob/main/TSPL.docc/ReferenceManual/Statements.md#conditional-compilation-block).

## Swift 6.4 build qualification — contract 0.5.0

Use the Swift Build engine explicitly and record clean/incremental, debug/release and standalone-consumer results. Do not hide a failed engine qualification behind an unreported native-engine fallback. Record target actor isolation, upcoming features, memory-safety settings, exact SDKs and the source of each adopted API's deployment availability. Build-associated SBOMs are distinct from package-graph inventories; report schema-validation failures and components outside the package graph. See [the upgrade record](Engineering/Swift64/README.md).

An API that a newer toolchain introduces is not automatically adoptable. Check its deployment availability against PLAT-02 before use. Where a convenience API is gated above the floor, express the same operation with primitives available at the floor: the contract fixes required behaviour, such as the explicit byte order in MEM-01, never the standard-library spelling used to achieve it. Record the substitution and the property being preserved. Byte-order sample access is the worked example — it uses explicit fixed-width integer conversion and does not raise the runtime floor.

## Command-line packaging — contract 0.4.0

The macOS/Linux executable is an independent product in each package and depends only on its own library. CLI entry points do not participate in library test linkage. `Scripts/install-cli.sh` installs/updates the binary and its section 1 manual together, supports an absolute prefix and DESTDIR staging, and verifies a prebuilt binary against VERSION. New package-manager distribution recipes must include the matching man page; copying only a binary is not a complete supported installation. Direct `man -M PREFIX/share/man <tool>` works without an index refresh. Native Linux execution still requires its own qualification.
