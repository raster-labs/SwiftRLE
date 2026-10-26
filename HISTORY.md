# History and provenance — SwiftRLE

## Milestone R0 foundation and baseline freeze — 23 October 2026

On 23 October 2026, the owner authorised creating `raster-labs/SwiftRLE` as the fifth standalone codec repository in the **Swift Image Compression Suite**, extracting and hardening the RLE (PackBits and DICOM PS3.5 Annex G frame profile) codec from [raster-labs/DICOMKit](https://github.com/raster-labs/DICOMKit).

| Item | Recorded identity |
| --- | --- |
| Target repository | [`raster-labs/SwiftRLE`](https://github.com/raster-labs/SwiftRLE) |
| Predecessor source repository | [`raster-labs/DICOMKit`](https://github.com/raster-labs/DICOMKit) |
| Pinned predecessor `main` SHA at R0 freeze | [`4b68d7e22829418c88e48dd53d98b25fee50d90d`](https://github.com/raster-labs/DICOMKit/commit/4b68d7e22829418c88e48dd53d98b25fee50d90d) (`v2.9.0`, `2026-10-23T13:45:06+05:30`, `"Prepare DICOMKit v2.9.0 release"`) |
| Earlier planning snapshot compared | [`9bd891660f0dc253871a92576f6f594f05feddb3`](https://github.com/raster-labs/DICOMKit/commit/9bd891660f0dc253871a92576f6f594f05feddb3) (`2026-10-23T12:04:33+05:30`, zero diff on RLE/codec extraction files relative to `4b68d7e2`) |
| Historical September handoff pin compared | [`c0dd2b682a8a921ca72745312d390eae0980dcd3`](https://github.com/raster-labs/DICOMKit/commit/c0dd2b682a8a921ca72745312d390eae0980dcd3) (`2026-09-17T14:37:42+05:30`) |
| Common contract reference pin (current `main`) | [`raster-labs/SwiftJ2K` @ `be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`](https://github.com/raster-labs/SwiftJ2K/commit/be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748) & [`raster-labs/SwiftJLS` @ `0791e54a5950bb8082af2218bce3800e03c777b9`](https://github.com/raster-labs/SwiftJLS/commit/0791e54a5950bb8082af2218bce3800e03c777b9) |
| Common contract review pin | [`raster-labs/SwiftJ2K` @ `a88413e5754ac9e85c0bd0fdde26754cc5702c8a`](https://github.com/raster-labs/SwiftJ2K/commit/a88413e5754ac9e85c0bd0fdde26754cc5702c8a) (`Contract 0.10.0`) |
| Historical handoff suite pins compared | `SwiftJ2K` [`8578b53f52292c04667ca6fca2944708ec198f3b`](https://github.com/raster-labs/SwiftJ2K/commit/8578b53f52292c04667ca6fca2944708ec198f3b), `SwiftJLS` [`6aab2622e3ed0b3ee1ec0c9e3a84564bd27fb2db`](https://github.com/raster-labs/SwiftJLS/commit/6aab2622e3ed0b3ee1ec0c9e3a84564bd27fb2db), `SwiftJXL` [`876e5cb285fd1db347a5907179da091959e1fff5`](https://github.com/raster-labs/SwiftJXL/commit/876e5cb285fd1db347a5907179da091959e1fff5), `SwiftJLI` [`2dc3e4a613df290f16904d5dc541202a44ca9862`](https://github.com/raster-labs/SwiftJLI/commit/2dc3e4a613df290f16904d5dc541202a44ca9862) |
| Predecessor licence | MIT (`Copyright (c) 2026 rasterdevapps`) — `DICOMKit` remains MIT |
| `SwiftRLE` licence | Apache-2.0 (`Copyright 2026 Raster Images Private Limited`), retaining full `DICOMKit` MIT notices and provenance |
| Published R0 foundation commit | [`b778f21cf0619418e739b625e5861d8584d20819`](https://github.com/raster-labs/SwiftRLE/commit/b778f21cf0619418e739b625e5861d8584d20819) (tree `1b32a8597427447ded73fe059ddab6c4c756e207`, formally accepted 23 October 2026) |
| Milestone R1 development branch | `milestone/r1` (branched from `b778f21cf0619418e739b625e5861d8584d20819`; standalone `Package.swift`, common API/owning storage and scalar `PackBitsEncoder`/`PackBitsDecoder`) |

## Pinned `DICOMKit` extraction and context paths (`4b68d7e22829418c88e48dd53d98b25fee50d90d`)

| `DICOMKit` path | SHA-256 at `4b68d7e2` | Bytes | Lines | Disposition in `SwiftRLE` / `DICOMKit` |
| --- | --- | --- | --- | --- |
| [`Sources/DICOMCore/RLECodec.swift`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Sources/DICOMCore/RLECodec.swift) | `59f7b00112760ce7b2342546185935dc457f17d6dcc1b4519b43374da18bca43` | 20,738 | 438 | Extract and harden PackBits & DICOM RLE frame kernels into `SwiftRLE` (`R1`/`R2`); retain public façade in `DICOMKit` (`D1`, deferred) |
| [`Tests/DICOMCoreTests/RLEEncoderTests.swift`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Tests/DICOMCoreTests/RLEEncoderTests.swift) | `0330bfaf229da5e021f8784e8abf10693d8e29e29ba937763f3bdd2ceeb71335` | 11,949 | 263 | Port and expand round-trip, strict-decode and row-boundary regressions into `Tests/SwiftRLETests/` (`R1`/`R2`) |
| [`Tests/DICOMCoreTests/CompressedPixelDataTests.swift`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Tests/DICOMCoreTests/CompressedPixelDataTests.swift) | `87d1599cd207b1439bbfef43ef218b8d2f126ec5d2152e06d3c983a474e1e4a8` | 16,350 | 514 | Port `RLECodecTests` literal/repeat/header checks into `Tests/SwiftRLETests/`; keep `EncapsulatedPixelDataTests` and `CodecRegistryTests` in `DICOMKit` |
| [`Tests/DICOMCoreTests/CodecFuzzTests.swift`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Tests/DICOMCoreTests/CodecFuzzTests.swift) | `9beeefd013b45370cdf6e3781e8f13cead49513d1c81717d7a2a03506b60772a` | 7,873 | 174 | Port sliced-`Data` (`startIndex != 0`), caller-buffer, adversarial offset, truncation and mutation tests into `Tests/SwiftRLETests/` (`R1`/`R2`) |
| [`Sources/DICOMCore/ImageCodec.swift`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Sources/DICOMCore/ImageCodec.swift) | `a594e77140f6ff441af4467a4edf798fcf997ded6e4e79326e7ec655e4edc215` | 20,986 | 512 | Stays in `DICOMKit`; inspected read-only for synchronous consumer protocol and `CodecRegistry` requirements |
| [`Sources/DICOMCore/PixelDataDescriptor.swift`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Sources/DICOMCore/PixelDataDescriptor.swift) | `f84f39a65615459e8eeee426578a8f8b64ee62fdd4a6c8053d3e30a16402386c` | 7,184 | 192 | Stays in `DICOMKit`; informs validated `RLEFrameDescriptor` and checked arithmetic in `SwiftRLE` (`R2`) |
| [`Sources/DICOMCore/PixelInterleaveSupport.swift`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Sources/DICOMCore/PixelInterleaveSupport.swift) | `b2ed2b0868695383d02313b164804692225e1d042e3a1edcf9b774d75cefe230` | 2,656 | 60 | Stays in `DICOMKit`; not copied into `SwiftRLE` (direct strided byte-lane scatter/gather replaces whole-frame interleave copies) |
| [`Sources/DICOMKit/Compression/CompressionManager.swift`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Sources/DICOMKit/Compression/CompressionManager.swift) | `eac2917b07a5540d781b36f90c1b9a36ddcec6a46e08cbb8245f3d4ee2a37410` | 64,774 | 1,281 | Stays in `DICOMKit`; inspected read-only for downstream transcoding/budget context |
| [`LICENSE`](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/LICENSE) | `4c0768004e1c88e30b7c28f3f4ea03998c351c89b81db0d05e333998acf8b9f4` | 1,070 | 21 | Preserved verbatim in [NOTICE](NOTICE) and [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) |

See [Documentation/BASELINE_AUDIT.md](Documentation/BASELINE_AUDIT.md) for the complete diff analysis between `c0dd2b682a8a921ca72745312d390eae0980dcd3`, `9bd891660f0dc253871a92576f6f594f05feddb3` and `4b68d7e22829418c88e48dd53d98b25fee50d90d`, caller inventory, defect reconciliation and executed predecessor test receipts.

## R1 common surface provenance

The common owning API is adapted from Apache-2.0 in-house reference code in `raster-labs/SwiftJ2K` at `be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`. Each destination below retains the corresponding `Sources/SwiftJ2K/` filename: `Sources/SwiftRLE/Errors.swift`, `ImageDescriptor.swift`, `ImageStorage.swift`, `Image.swift`, `Options.swift`, `Telemetry.swift` and the common portions of `CodecAPI.swift`. RLE-specific configurations, PackBits operations and audit regressions are added in SwiftRLE. DICOMKit-derived kernel and test paths retain their separate per-file MIT provenance comments and full notices.

## R5 provenance reconciliation — 24 October 2026

R0–R4 are accepted and merged; R5 starts from `d43bc2aaec0c511c6e583dea42dcb57298d8a000`. The extraction and common API pins above remain unchanged. R5 adds no codec algorithm source or external runtime dependency. `Qualification/Runtime/main.swift` is independently authored synthetic qualification code using coordinate/component-derived samples and explicit PackBits/DICOM packet vectors, dedicated to CC0; the harness and qualification runners carry Apache-2.0 SPDX headers. Existing DICOMKit-derived source/test comments and both full inherited MIT notices remain preserved. See [R5 qualification](Documentation/R5_QUALIFICATION.md) for source/product binding and platform gaps.

## R5 available-environment qualification and owner waiver — 26 October 2026

DEC-11 records the owner's direct instruction to use available native macOS and iPhone/iPad iOS 26 simulator validation and complete R5 acceptance/PR #5 merge. Qualification work is complete for that approved scope. Exact macOS 26.0 runtime and physical iPhone/iPad tests remain UNEXECUTED; the owner explicitly waived them as R5 acceptance gates. Existing other-platform evidence remains supplemental. The documentation closure changes no production code, tests/drivers/CI, manifest/version, pinned contracts or licences and performs no new validation runs. Final independent acceptance, exact-final-head CI/artifact review and merge-tree verification are tracked in the PR/audit workflow; this record does not claim the PR merged or authorize a tag/release or DICOMKit cutover.
