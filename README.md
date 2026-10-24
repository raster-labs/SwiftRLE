# SwiftRLE

Standalone PackBits and DICOM RLE frame compression library for the **Swift Image Compression Suite**.

**Status: R2 implemented locally for independent audit.** The package provides scalar PackBits bytes and strict DICOM RLE frames with direct strided 8/16-bit mono, unsigned palette/RGB/YBR_FULL processing, canonical meaningful-bit handling and an explicit raw allocated-cell route. R1 was accepted and merged through PR #1. R2 publication/CI/acceptance is pending; CLI/cross-codec work (R3), long fuzz/sanitizer/performance gates (R4) and final platform qualification (R5) remain deferred. No release or tag is claimed.

See [R2 profile and validation notes](Documentation/R2_FRAME_PROFILE.md) for exact semantics, memory bounds and repeatable host checks.

SwiftRLE extracts and hardens the pure-Swift RLE (PackBits and DICOM PS3.5 Annex G frame profile) implementation from [raster-labs/DICOMKit](https://github.com/raster-labs/DICOMKit) into a standalone package with no runtime dependency on `DICOMKit`, any sibling codec, `CompressionFamily` or `SwiftCompressionFamily`. `SwiftRLE` is licensed under **Apache-2.0** ([LICENSE](LICENSE), [NOTICE](NOTICE)) while preserving full **MIT** copyright and permission notices and source provenance from `DICOMKit` ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [HISTORY.md](HISTORY.md)). `DICOMKit` itself remains MIT-licensed.

## Approved package and CLI identity

- **Repository**: `https://github.com/raster-labs/SwiftRLE`
- **Package & library product / public module**: `SwiftRLE`
- **CLI executable product**: `swiftrle-cli` (target `SwiftRLECLI`, manual page `ManPages/swiftrle-cli.1`, avoiding case-insensitive APFS target/product collisions under `CLI_CONTRACT.md` CLI-01)
- **Intended platform baseline**: Swift tools `6.2` minimum (`6.4` primary qualification toolchain), Swift 6 language mode with complete concurrency checking; Apple deployment minima `macOS 26.0`, `iOS/iPadOS 26.0`, `tvOS 26.0`, `visionOS 26.0` and `watchOS 26.0` (library target); Linux reference environment Ubuntu 24.04 on `aarch64` and `x86_64`. These are target requirements, not completed platform qualification claims.

## Start reading

- [Coding-agent instructions](AGENTS.md) and [R0–R5 implementation plan & R1 handoff](IMPLEMENTATION.md).
- [Baseline source & test audit](Documentation/BASELINE_AUDIT.md) and [common contract inventory](Documentation/CONTRACT_INVENTORY.md).
- [Capability & profile matrix](Documentation/CAPABILITY_MATRIX.md) and [owner decision record](Documentation/DECISION_RECORD.md).
- Common suite specifications: [SUITE_POLICY.md](Documentation/SUITE_POLICY.md) (`0.10.0`), [CLI_CONTRACT.md](Documentation/CLI_CONTRACT.md) (`0.10.0`), [COMMON_API.md](Documentation/COMMON_API.md) (`0.7.0`), [MEMORY_CONTRACT.md](Documentation/MEMORY_CONTRACT.md) (`0.7.0`), [PERFORMANCE.md](Documentation/PERFORMANCE.md) (`0.7.0`), [PLATFORMS.md](Documentation/PLATFORMS.md) (`0.7.0`), [TESTING.md](Documentation/TESTING.md) (`0.7.0`) and [COMMON_CONTRACT_SHA256.txt](Documentation/COMMON_CONTRACT_SHA256.txt).
- [History and source provenance](HISTORY.md), [third-party & MIT notices](THIRD_PARTY_NOTICES.md), [change log](CHANGELOG.md), [security policy](SECURITY.md), [contributing guide](CONTRIBUTING.md), [Apache-2.0 licence](LICENSE) and [NOTICE](NOTICE).

## Scope boundary

SwiftRLE will provide two explicit levels:

1. **Generic PackBits byte engine**: lossless byte-stream and row-constrained PackBits compression/decompression with explicit expected decoded byte counts and bounded resource limits.
2. **DICOM RLE frame profile**: 64-byte little-endian segment offset header and MSB-to-LSB byte-plane segments (DICOM PS3.5 Section 8.2.2 and Annex G) paired with a validated external `RLEFrameDescriptor` and direct strided scatter/gather into `ImageDestination` / from `Image`.

SwiftRLE is not a DICOM file/dataset parser, transfer-syntax registry or display rendering pipeline. Downstream `DICOMKit` adapter integration (`D0`–`D4`) is deferred until `SwiftRLE` milestones `R0`–`R5` are independently implemented and accepted.
