# Milestone R0 — Owner decision register and governance record

**Date**: 23 October 2026  
**Milestone**: `R0`  
**Status**: Owner-approved decisions recorded; governs `SwiftRLE` milestones `R0`–`R5` and deferred `DICOMKit` milestones `D0`–`D4`.

---

## 1. Approved decisions

| Decision ID | Area | Approved decision | Rationale and implementation impact |
| --- | --- | --- | --- |
| **DEC-01** | **Repository & organisation** | Create [`https://github.com/raster-labs/SwiftRLE`](https://github.com/raster-labs/SwiftRLE) consistent with the public `raster-labs` suite (`SwiftJ2K`, `SwiftJLS`, `SwiftJXL`, `SwiftJLI`, `DICOMKit`). | Supersedes the historical `Raster-Lab/SwiftRLE` spelling in the September 2026 handoff documents. Never overwrite an existing repository. |
| **DEC-02** | **Licensing & provenance** | License `SwiftRLE` under **Apache-2.0** ([LICENSE](../LICENSE), [NOTICE](../NOTICE)), extending [SUITE_POLICY.md](SUITE_POLICY.md) `POL-07` to `SwiftRLE`, while retaining full **MIT** copyright and permission notices and extraction provenance from `DICOMKit` ([THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), [HISTORY.md](../HISTORY.md)). | Aligns `SwiftRLE` with `SwiftJ2K`, `SwiftJLS`, `SwiftJXL` and `SwiftJLI` (all Apache-2.0). `DICOMKit` remains MIT-licensed. |
| **DEC-03** | **Platform deployment floor** | `SwiftRLE` targets **Apple OS 26.0** (`macOS 26.0`, `iOS/iPadOS 26.0`, `tvOS 26.0`, `visionOS 26.0`, `watchOS 26.0`) plus Linux (`Ubuntu 24.04` on `aarch64` and `x86_64`), with Swift tools `6.2` minimum and `6.4` primary qualification toolchain. Staged `DICOMKit` OS 26 adoption is approved for a later separately authorised release line. | Complies with `SUITE_POLICY.md` (`0.9.0` Decision D3) and `PLATFORMS.md` (`0.7.0` PLAT-02). `DICOMKit` stays on its existing platform floor (`.macOS(.v15)`, `.iOS(.v18)`, `.tvOS(.v18)`, `.visionOS(.v2)`) and is untouched during `R0`–`R5`. |
| **DEC-04** | **Package, module & CLI naming** | Package and library/module name: `SwiftRLE`. CLI executable product: **`swiftrle-cli`**. Executable target: **`SwiftRLECLI`**. Manual page: **`ManPages/swiftrle-cli.1`**. | Complies with `CLI_CONTRACT.md` (`0.10.0` CLI-01), preventing case-insensitive APFS build directory collisions between `SwiftRLE.build` and `swiftrle.build` on macOS. |
| **DEC-05** | **Sequencing & `DICOMKit` boundary** | Execute `SwiftRLE` milestones **`R0`–`R5` first**, one milestone per fresh chat, with independent engineering audit and formal acceptance between milestones. Defer all `DICOMKit` changes (`D0`–`D4`) until `SwiftRLE` is independently qualified. | `R3` verifies the `swiftrle-cli` tool, a separately packaged real `SwiftRLE <-> SwiftJLS` shared-storage harness and a `DICOMKit`-facing adapter proof **outside** `DICOMKit`. Zero edits to `DICOMKit` or sibling codec repositories are permitted during `R0`–`R5`. |
| **DEC-06** | **Common API & memory contract** | Implement the normative `COMMON_API.md` (`0.7.0`) and `MEMORY_CONTRACT.md` (`0.7.0`) types and call shapes (`Encoder`, `Decoder`, `ImageDescriptor`, `PlaneDescriptor`, `Image`, `ImageDestination`, `ReadOnlyImageStorage`, `WritableImageStorage`, `OwnedImageStorage`, `StorageWriteLease`, `ResourceLimits`, `OperationReport`, `CodecCapabilities`, `CodecError`), with async `encode`/`decode`, synchronous `inspect`, explicit `encodeSynchronously`/`decodeSynchronously` wrappers (`API-03`) and justified RLE extensions (`API-13`). | Rejects unsupported substitute type names or synchronous-only replacements of the common surface. Preserves module independence (`SwiftRLE` imports no sibling codec or `CompressionFamily`). |
| **DEC-07** | **Version identifiers & release tags** | Use `0.1.0-dev.1` as the initial development identifier when `VERSION` / CLI support arrives, and `1.0.0` as the intended first stable target after full `R5` qualification. No git tag or GitHub release is authorised during `R0`–`R5` scaffolding/implementation without separate explicit release instruction. | Prevents premature stability or conformance claims before all oracle, sanitizer, fuzz, cross-codec and platform gates pass. |

---

## 2. Remote repository provisioning status at R0

The exact public repository [`https://github.com/raster-labs/SwiftRLE`](https://github.com/raster-labs/SwiftRLE) has been provisioned and authorised write access has been verified. The local repository has `origin` configured to `https://github.com/raster-labs/SwiftRLE.git`, while the remote remains empty prior to audited publication.

Final R0 publication and acceptance remain pending independent verification of these updated records and the published initial commit. Operational credential and access-verification details are retained in the local audit receipt, not in public repository documentation.
