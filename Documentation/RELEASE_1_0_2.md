# SwiftRLE 1.0.2 source-patch release notes

This document is the dated **11 November 2026 release record** for the `SwiftRLE` `1.0.2` source-patch line prepared on `release/1.0.2` from verified `main` commit `f81855537674ac5c3d64d6a984386bc54988b176` (PR #10 merge of `750b400e9cf70915143c2c9dd181cd2e37fa547d`). [`v1.0.0`](https://github.com/raster-labs/SwiftRLE/releases/tag/v1.0.0) (`640e469fc9f6f9b9da59962b7f3b5a122f96373b`; see [1.0.0 release notes](RELEASE_1_0_0.md)) and [`v1.0.1`](https://github.com/raster-labs/SwiftRLE/releases/tag/v1.0.1) (`4eaaf9139d2f7a836af142b4fdb32f3b9582e005`; see [1.0.1 release notes](RELEASE_1_0_1.md)) remain immutable published source releases. Current pull-request and tag/release publication status is tracked on [GitHub pull requests](https://github.com/raster-labs/SwiftRLE/pulls) and [GitHub releases](https://github.com/raster-labs/SwiftRLE/releases): the governed publication workflow proceeds through `release/1.0.2` targeting `main`, all five required exact-head CI checks, merge into `main` (preserving `release/1.0.2`), immutable annotated `v1.0.2` tag creation on the merged commit, and GitHub source-release publication. No prebuilt binary distribution is claimed.

## Changes packaged relative to `v1.0.1` (`4eaaf9139d2f7a836af142b4fdb32f3b9582e005`)

- **Relicensing to the MIT License (`DEC-13`, [PR #10](https://github.com/raster-labs/SwiftRLE/pull/10), `f81855537674ac5c3d64d6a984386bc54988b176`)**: Under owner decision `DEC-13` ([DECISION_RECORD.md](DECISION_RECORD.md)), `SwiftRLE` is relicensed from Apache-2.0 to the MIT License (`Copyright (c) 2026 Raster Images Private Limited`; [LICENSE](../LICENSE), [NOTICE](../NOTICE), [THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md)), superseding `DEC-02`. All 53 repository source, test, script and manifest headers carry `SPDX-License-Identifier: MIT`, while preserving both `DICOMKit`'s updated MIT copyright holder notice (`Copyright (c) 2026 Raster Images Private Limited` at `88758ba6168e670f16f3c6a08ca2245db39629f2`) and its original R0 extraction-pin MIT notice (`Copyright (c) 2026 rasterdevapps` at `4b68d7e22829418c88e48dd53d98b25fee50d90d`).
- **Downstream `DICOMKit` (`D0`–`D4`) completion documentation ([PR #10](https://github.com/raster-labs/SwiftRLE/pull/10), `f81855537674ac5c3d64d6a984386bc54988b176`)**: Records that downstream `DICOMKit` (`D0`–`D4`) integration is completed in [`raster-labs/DICOMKit`](https://github.com/raster-labs/DICOMKit) `v3.0.0` ([PR #240](https://github.com/raster-labs/DICOMKit/pull/240) `cd3528022d` / `0d74f44194` and [PR #244](https://github.com/raster-labs/DICOMKit/pull/244) `79265e4d5f` / `9b402fef53`), while `SwiftRLE` remains a standalone dependency-free package. PR #10 head CI run `42804395239` and post-merge `main` CI run `42809504367` passed all five required jobs.
- **`1.0.2` version, CLI and manual metadata**: Advances `VERSION`, `swiftrle-cli` version/help literals (`Sources/SwiftRLECLI/CLIRunner.swift`) and `ManPages/swiftrle-cli.1` metadata/date (`11 November 2026`) to `1.0.2`. Codec algorithms, public API, `Package.swift`, Apple OS `26.0` platform floors, Swift tools `6.2` minimum (`6.4` primary), zero external dependencies, all seven pinned common contracts ([COMMON_CONTRACT_SHA256.txt](COMMON_CONTRACT_SHA256.txt)) and tests/drivers/CI remain unchanged.

## Swift Package Manager usage

Semantic-version resolution follows published immutable git tags on [GitHub releases](https://github.com/raster-labs/SwiftRLE/releases):

```swift
dependencies: [
    .package(url: "https://github.com/raster-labs/SwiftRLE.git", from: "1.0.2")
],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "SwiftRLE", package: "SwiftRLE")
    ])
]
```

## Qualification scope and limits

- **Preserved algorithmic and security evidence**: Because `1.0.2` changes only licensing headers/notices, documentation and `1.0.2` version/help/manual metadata relative to `v1.0.1` (`4eaaf9139d2f7a836af142b4fdb32f3b9582e005`), the accepted R0–R5 implementation, `1.0.1` 30 October 2026 affected-path ASan/TSan (`49/49` tests, `27` two-way `DCMTK` profiles each), one-hour deterministic `packbits` and `nrrd` mutation campaigns, `iOS 26.0` simulator (`42/42` profiles each on iPhone and iPad) and R3/R4 DICOM-frame/shared-storage evidence ([RELEASE_1_0_1.md](RELEASE_1_0_1.md), [R5_QUALIFICATION.md](R5_QUALIFICATION.md), [R4_QUALIFICATION.md](R4_QUALIFICATION.md)) remain unchanged within their documented bounds.
- **Waived / unexecuted (unchanged DEC-11)**: Exact `macOS 26.0` runtime execution and physical iPhone/iPad hardware tests remain **UNEXECUTED** and **WAIVED_BY_OWNER** as R5 acceptance gates under DEC-11 ([DECISION_RECORD.md](DECISION_RECORD.md)). Historical Linux (`Ubuntu 24.04` `x86_64`/`aarch64`), `watchOS`, `tvOS` and `visionOS` evidence remains supplemental under DEC-10/DEC-11. No prebuilt executable distribution or clinical-conformance certification is claimed.
