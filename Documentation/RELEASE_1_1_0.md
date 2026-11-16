# SwiftRLE 1.1.0 feature and performance release notes

This document is the dated **16 November 2026 release record** for `SwiftRLE` `1.1.0` (`v1.1.0`) prepared on `main` over verified `v1.0.2` (`31704547c32aa967ef24d84539999a7228279934`). [`v1.0.0`](https://github.com/raster-labs/SwiftRLE/releases/tag/v1.0.0) (`640e469fc9f6f9b9da59962b7f3b5a122f96373b`; see [1.0.0 release notes](RELEASE_1_0_0.md)), [`v1.0.1`](https://github.com/raster-labs/SwiftRLE/releases/tag/v1.0.1) (`4eaaf9139d2f7a836af142b4fdb32f3b9582e005`; see [1.0.1 release notes](RELEASE_1_0_1.md)), and [`v1.0.2`](https://github.com/raster-labs/SwiftRLE/releases/tag/v1.0.2) (`31704547c32aa967ef24d84539999a7228279934`; see [1.0.2 release notes](RELEASE_1_0_2.md)) remain immutable published source releases.

## Changes packaged relative to `v1.0.2` (`31704547c32aa967ef24d84539999a7228279934`)

- **SWAR / `SIMD16<UInt8>` PackBits byte-run kernels (`be49879`)**: Accelerates PackBits run-length and literal span scanning and emission under `Backend.accelerated` (`ExecutionPolicy.automatic` / `.preferred(.accelerated)` / `.required(.accelerated)`) while preserving exact bit-identical PackBits framing and `ExecutionPolicy.scalarCPU` reference execution.
- **Bounded multi-worker row-band DICOM RLE encode/decode (`BoundedParallelPool`, `be49879`, `2cc7e06`)**: Adds deterministic row-band parallel DICOM RLE frame encoding and decoding bounded by `ResourceLimits.maximumWorkers`, strict workspace byte accounting (`maximumWorkspaceBytes` / `maximumMemoryBytes`), and cooperative task cancellation bridging across worker bands, matching 1-worker output bit-for-bit across all 1..15 segment layouts.
- **Zero-hop synchronous codec APIs (`be49879`)**: Provides direct synchronous `encodeSynchronously` / `decodeSynchronously` entry points without Swift concurrency executor hop overhead for in-memory caller pipelines such as `DICOMKit` `v3.2.0`.
- **`1.1.0` version, CLI and manual metadata**: Advances `VERSION`, `swiftrle-cli` version/help literals (`Sources/SwiftRLECLI/CLIRunner.swift`) and `ManPages/swiftrle-cli.1` metadata/date (`16 November 2026`) to `1.1.0`. `Package.swift`, Apple OS `26.0` platform floors, Swift tools `6.2` minimum (`6.4` primary), zero external dependencies, and all seven pinned common contracts ([COMMON_CONTRACT_SHA256.txt](COMMON_CONTRACT_SHA256.txt)) remain unchanged.

## Swift Package Manager usage

```swift
dependencies: [
    .package(url: "https://github.com/raster-labs/SwiftRLE.git", from: "1.1.0")
],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "SwiftRLE", package: "SwiftRLE")
    ])
]
```

## Qualification scope and limits

- **Verified host and cross-oracle gates**: Passes the expanded repository unit, ownership, CLI, parallel 1T==NT determinism, workspace-limit, cancellation, and `DCMTK` (`dcmcrle`/`dcmdrle`) / `libtiff` interoperability suites in Debug and Release modes on native macOS `arm64`, with `7/7` shared contract SHA-256 checks intact.
- **Waived / unexecuted (unchanged DEC-11)**: Exact `macOS 26.0` runtime execution and physical iPhone/iPad hardware tests remain **UNEXECUTED** and **WAIVED_BY_OWNER** as R5 acceptance gates under DEC-11 ([DECISION_RECORD.md](DECISION_RECORD.md)). No prebuilt executable distribution or clinical-conformance certification is claimed.
