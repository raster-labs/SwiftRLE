# R1 validation and bounded public surface

R1 provides raw PackBits byte operations and the common owning image/storage API. Image-level DICOM frame operations reject as unsupported until R2. No CLI, DICOMKit integration, release or broad platform qualification is implied.

## Independent audit and executed host evidence

On 23 October 2026, independent checks of the submitted R1 source reproduced five defects. Scoped repairs bound finite deadline conversion, enforce combined compressed/input/output admission, make an incremental append failure terminal, correct the greedy two-byte-repeat encoder's worst-case expansion bound, and enforce deadlines after progress callbacks. Regression tests include the original failing inputs, exhaustive short binary packet patterns, exact memory boundaries and cancellation during operations. The original failure receipts are retained in the audit record.

The repaired source passed **25 tests in four suites, zero failures or skips**, in debug and release, using Apple Swift 6.4 (`swiftlang-6.4.0.34.1`, `clang-2100.3.34.1`), Xcode 27.0 (`27A266a`), macOS 27.0.1 (`26A434`), Apple M4 arm64. Swift Build was selected explicitly (`--build-system swiftbuild`). The independent `Examples/Consumer` executed successfully; the package manifest has zero dependencies. These are host results and do not establish the exact OS 26.0 runtime or Swift 6.2 qualification.

Two-way libtiff 4.7.2 interoperability runs as part of the host test suite. The deterministic synthetic fixture is 17 × 13 unsigned 8-bit greyscale; its generator and single-strip TIFF extraction are in `PackBitsTests.swift`. Payload SHA-256 is `58b86c3d857bb10a47820bce24a71cdcc9da6bf80f807ceaee14d24290c81e47`; the libtiff PackBits strip is 130 bytes at offset 8, SHA-256 `da584860fe53d45c2f47902e6da2979e964931c9cd161843532750a829a2c1d3`. Both directions compare the exact payload. Host tests require `tiffcp` via `SWIFTRLE_TIFFCP` or `PATH`; a missing oracle fails. Apple-device library builds do not invoke an external oracle.

## Reproduction and CI gates

Run `python3 Scripts/validate-r1.py --build-system swiftbuild --output /absolute/scratch/directory` with Swift 6.4 and libtiff installed. The script verifies seven pinned contract hashes, records source hashes and environment, checks dependency independence, runs debug/release tests and the consumer, and rejects a missing/zero test summary. Output includes JSON receipts and logs. Swift 6.2 compatibility uses the explicitly selected `native` build engine; this is a separate matrix entry, not a fallback from failed Swift Build qualification.

The milestone workflow checks out the exact PR head and requires:

- Native Ubuntu 24.04 x86_64 and aarch64 correctness, each with official Swift 6.2.4 and 6.4.0 containers.
- Native macOS arm64 correctness with Xcode's Swift 6.2 and the official Swift 6.4.0 toolchain.
- OS 26 SDK library builds for iOS, tvOS, visionOS and watchOS, including simulators. These are compile checks, not runtime/device results.

All seven jobs must actually execute and pass before Codex merges. Workflow presence is not passing CI. CI is pending the first PR at this local checkpoint; its receipts report the toolchain/oracle versions actually used. Runner and toolchain choices follow the [GitHub runner inventory](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md), [official Swift Linux downloads](https://www.swift.org/install/linux/ubuntu/24_04/) and [official macOS toolchains](https://www.swift.org/install/macos/).

## Resource and reporting semantics

Raw byte APIs return their final `Data` separately from `OperationReport`. `data.count` is the logical output byte count. Zero pixel allocations in a raw-byte report means no `OwnedImageStorage`/`Image` allocation; it does not mean no heap allocation. Foundation's backing capacity, allocator overhead and growth-allocation count are unmeasured, not asserted to be zero. The kernels use no additional full decoded buffer or packet/row array workspace. The memory admission budget covers logical input and output buffer bytes; process RSS includes unmeasured runtime and allocator overhead.

Incremental sessions conservatively charge cumulative compressed bytes plus the declared final output size, including previously released chunks. Every failed append permanently closes the session and prevents publication. Deadlines must be positive, finite and representable in signed 64-bit nanoseconds. Synchronous byte callbacks run inline on the calling execution context; async image operations use the generic executor. Callbacks must return promptly. A callback that exceeds the deadline prevents successful output publication.

## Remaining qualification

R2–R5 retain their explicit DICOM interoperability, real shared-storage transcode, sanitizer/race, sustained fuzz, controlled performance, clean URL consumer and platform/runtime gates. Native Intel macOS, exact minimum-OS runtime, physical devices and unavailable environments remain unexecuted until actual evidence exists. DICOMKit D0–D4 stay deferred. No tag or release is authorised.
