# Owner decision register and governance record — SwiftRLE

**Date**: 23 October 2026  
**Current stage**: R0–R5 accepted; post-R5 1.0.0 source-release line (26 October 2026). Earlier decisions remain dated historical records.
**Status**: Owner-approved decisions recorded; governs `SwiftRLE` milestones `R0`–`R5` and deferred `DICOMKit` milestones `D0`–`D4`.

---

## 1. Approved decisions

| Decision ID | Area | Approved decision | Rationale and implementation impact |
| --- | --- | --- | --- |
| **DEC-01** | **Repository & organisation** | Create [`https://github.com/raster-labs/SwiftRLE`](https://github.com/raster-labs/SwiftRLE) consistent with the public `raster-labs` suite (`SwiftJ2K`, `SwiftJLS`, `SwiftJXL`, `SwiftJLI`, `DICOMKit`). | Supersedes the historical `Raster-Lab/SwiftRLE` spelling in the September 2026 handoff documents. Never overwrite an existing repository. |
| **DEC-02** | **Licensing & provenance** | License `SwiftRLE` under **Apache-2.0** ([LICENSE](../LICENSE), [NOTICE](../NOTICE)), extending [SUITE_POLICY.md](SUITE_POLICY.md) `POL-07` to `SwiftRLE`, while retaining full **MIT** copyright and permission notices and extraction provenance from `DICOMKit` ([THIRD_PARTY_NOTICES.md](../THIRD_PARTY_NOTICES.md), [HISTORY.md](../HISTORY.md)). | Aligns `SwiftRLE` with `SwiftJ2K`, `SwiftJLS`, `SwiftJXL` and `SwiftJLI` (all Apache-2.0). `DICOMKit` remains MIT-licensed. |
| **DEC-03** | **Platform deployment floor** | `SwiftRLE` targets **Apple OS 26.0** (`macOS 26.0`, `iOS/iPadOS 26.0`, `tvOS 26.0`, `visionOS 26.0`, `watchOS 26.0`) plus Linux (`Ubuntu 24.04` on `aarch64` and `x86_64`), with Swift tools `6.2` minimum and `6.4` primary qualification toolchain. Staged `DICOMKit` OS 26 adoption is approved for a later separately authorised release line. | Complies with `SUITE_POLICY.md` (`0.9.0` Decision D3) and `PLATFORMS.md` (`0.7.0` PLAT-02). `DICOMKit` stays on its existing platform floor (`.macOS(.v15)`, `.iOS(.v18)`, `.tvOS(.v18)`, `.visionOS(.v2)`) and is untouched during `R0`–`R5`. |
| **DEC-04** | **Package, module & CLI naming** | Package and library/module name: `SwiftRLE`. CLI executable product: **`swiftrle-cli`**. Executable target: **`SwiftRLECLI`**. Manual page: **`ManPages/swiftrle-cli.1`**. | Complies with `CLI_CONTRACT.md` (`0.10.0` CLI-01), preventing case-insensitive APFS build directory collisions between `SwiftRLE.build` and `swiftrle.build` on macOS. |
| **DEC-05** | **Sequencing & `DICOMKit` boundary** | Execute `SwiftRLE` milestones **`R0`–`R5` first**, one milestone per explicit bounded assignment, with independent engineering audit and formal acceptance between milestones. Defer all `DICOMKit` changes (`D0`–`D4`) until `SwiftRLE` is independently qualified. | `R3` verifies the `swiftrle-cli` tool, a separately packaged real `SwiftRLE <-> SwiftJLS` shared-storage harness and a `DICOMKit`-facing adapter proof **outside** `DICOMKit`. Zero edits to `DICOMKit` or sibling codec repositories are permitted during `R0`–`R5`. |
| **DEC-06** | **Common API & memory contract** | Implement the normative `COMMON_API.md` (`0.7.0`) and `MEMORY_CONTRACT.md` (`0.7.0`) types and call shapes (`Encoder`, `Decoder`, `ImageDescriptor`, `PlaneDescriptor`, `Image`, `ImageDestination`, `ReadOnlyImageStorage`, `WritableImageStorage`, `OwnedImageStorage`, `StorageWriteLease`, `ResourceLimits`, `OperationReport`, `CodecCapabilities`, `CodecError`), with async `encode`/`decode`, synchronous `inspect`, explicit `encodeSynchronously`/`decodeSynchronously` wrappers (`API-03`) and justified RLE extensions (`API-13`). | Rejects unsupported substitute type names or synchronous-only replacements of the common surface. Preserves module independence (`SwiftRLE` imports no sibling codec or `CompressionFamily`). |
| **DEC-07** | **Version identifiers & release tags** | Use `0.1.0-dev.1` as the initial development identifier when `VERSION` / CLI support arrives, and `1.0.0` as the intended first stable target after full `R5` qualification. No git tag or GitHub release is authorised during `R0`–`R5` scaffolding/implementation without separate explicit release instruction. | Prevents premature stability or conformance claims before all oracle, sanitizer, fuzz, cross-codec and platform gates pass. |
| **DEC-08** | **Milestone branch, PR & Codex merge policy** | Every milestone (`R1`–`R5`) uses a dedicated branch (`milestone/r1` through `milestone/r5`) branched from the latest accepted/merged `main` commit. No direct commits or pushes to `main` are permitted for `R1`–`R5`. After independent Codex audit and formal acceptance of a milestone's local contents, the authorised publication step is to commit and push `milestone/rN` and open **one** pull request targeting `main` for Codex exact-head CI review. The owner explicitly authorises Codex to review required CI on the exact accepted PR head and merge it into `main`. Antigravity must not merge; no auto-merge, branch deletion or tag/release is authorised. | Enforces clean per-milestone PR boundaries, CI visibility and explicit Codex acceptance and exact-head CI gates before starting the next milestone in the existing goal chat. |

---

## 2. Repository publication and milestone status

- **Milestone R0 (Accepted & Published)**: Published on `main` at commit [`b778f21cf0619418e739b625e5861d8584d20819`](https://github.com/raster-labs/SwiftRLE/commit/b778f21cf0619418e739b625e5861d8584d20819) (tree `1b32a8597427447ded73fe059ddab6c4c756e207`) and formally accepted by independent audit on 23 October 2026.
- **Milestone R1 (Accepted and merged)**: PR #1 merged at `60af084d25522fafebb71abfeb37f4635dc2af3b` after independent audit and exact-head CI; R2 begins from that accepted main.

- **Milestone R5 (Accepted and merged)**: PR #5 merged at `942dfb9135321bd8b3339fbbdf2388012d72c4b8` after all five final-head jobs in run `40273685051`, artifact audit and merge-tree verification, within DEC-11 scope.

## 3. Owner workflow update — 24 October 2026

**DEC-09** supersedes the fresh-chat/Antigravity execution route in DEC-05/DEC-08: R2–R5 use GPT-6.1 Sol implementation agents within the existing goal chat, with one bounded milestone at a time and independent root Codex audit. Branch, audit-before-publication, exact-head CI and merge gates remain required. R1 was accepted and merged through PR #1 at `60af084d25522fafebb71abfeb37f4635dc2af3b`; R2 starts from that base. No tag, release, auto-merge, deletion or downstream integration authority is added.

## 4. R5 qualification status — 24 October 2026

Historical checkpoint: current validation scope and waiver authority are recorded in DEC-10 and DEC-11 below.

R2, R3 and R4 were independently accepted and merged in sequence; R4 main is `d43bc2aaec0c511c6e583dea42dcb57298d8a000`. R5 starts on `milestone/r5` from that merge. R5 may publish independently audited local contents for native Intel and other attainable remote CI checks, while mandatory unavailable target/device gates remain open. Final R5 acceptance/merge still requires all mandatory gates; no hardware waiver, stable version/tag/release, downstream cutover or change to the seven pinned contracts is implied. See [R5 qualification](R5_QUALIFICATION.md).

## 5. Owner validation scope — 24 October 2026

Historical decision: the no-waiver clause below is superseded by DEC-11 on 26 October 2026.

**DEC-10**: The owner instructed, “limit the validation to macOS and iOS”. Required R5 validation is therefore macOS (native arm64 and Intel x86_64, Swift 6.2 and 6.4) and iOS/iPadOS. Required CI comprises four native macOS/toolchain entries retaining core, CLI, independent oracle and peer integration coverage, plus one iOS 26.0 device/simulator SDK-build job. Previously executed Linux/watchOS/tvOS/visionOS evidence is retained as supplemental; missing validation on those platforms does not block R5 under this current owner scope.

This explicit owner scope takes precedence for R5 acceptance without changing any pinned contract bytes or package manifest targets, removing codec features, or asserting qualification of unexecuted environments. The owner did not waive exact macOS 26.0 runtime or representative physical iPhone/iPad gates; these remain unexecuted unless actual evidence or a separate explicit waiver is recorded. No new validation outside macOS/iOS is required. DICOMKit remains strictly read-only throughout R5; no DICOMKit production code or cutover is included.

## 6. Available-environment qualification and explicit gate waiver — 26 October 2026

Historical authorization checkpoint: R5 was subsequently accepted and merged; its result and separate stable-release authority are recorded in DEC-12.

**DEC-11** records the direct owner instruction: “Use the available macOS and iOS simulator validation. Waive exact macOS 26.0 and physical-device tests as R5 gates, keep them documented as unexecuted, and complete R5 acceptance and merge PR #5.” This supersedes DEC-10's no-waiver clause for R5 acceptance.

The required qualification scope is available native macOS validation and iPhone/iPad iOS 26 simulator validation. Exact macOS 26.0 runtime and physical iPhone/iPad tests remain **UNEXECUTED**, with their R5 acceptance-gate status **WAIVED_BY_OWNER**; they are not passed tests or inferred hardware qualification. Other-platform evidence remains supplemental. Qualification work is complete for this owner-approved scope; final independent audit, all five exact-final-head CI checks and artifact review, PR #5 acceptance/merge and merge-tree verification remain recorded by the independent audit/publication workflow. The implementation agent does not self-accept or claim the PR merged.

The owner authorizes completing acceptance and merging PR #5 only. Pinned contracts, package targets, production code, tests/drivers/CI, version and licences are unchanged by this documentation closure. This grants no DICOMKit edits/cutover, new platform validation, tag/release, auto-merge, direct-main push or branch deletion.

## 7. Stable 1.0.0 source release and continued downstream deferral — 26 October 2026

**DEC-12** records the direct owner instruction: “Proceed Stable release and Documentation cleanup. DICOMKit review is going on so D0 - D4 will be completed later.” R5 was independently accepted and merged through PR #5 at `942dfb9135321bd8b3339fbbdf2388012d72c4b8` after all five required final-head CI jobs in run `40273685051`, artifact audit and merge-tree verification.

This is the separate explicit release authority anticipated by DEC-07. Prepare version `1.0.0` on `release/1.0.0`, with only version/help/manual metadata and post-merge documentation/release notes. The independent root auditor/publisher owns local audit, one release PR, all five exact-final-head CI checks/artifact review, merge/tree verification, an annotated immutable `v1.0.0` tag on the verified merge, a fresh tagged semantic-version consumer and the stable source GitHub release. Actual tag/release identities and publication state are recorded by GitHub and the publication audit; this decision is authorization, not a claim publication already occurred. The implementation agent must not commit, push, open/merge PRs, tag or publish releases.

The release contains the Swift package and CLI/manual sources; it makes no prebuilt executable distribution claim. Available native macOS and iPhone/iPad iOS 26 simulator evidence is the approved qualification scope. Exact macOS 26.0 and physical iPhone/iPad tests remain UNEXECUTED and WAIVED_BY_OWNER as R5 gates under DEC-11; supplemental platforms are not promoted to fully qualified support. No codec/core/API, manifest/platform, CI, common-contract, test/driver or licence change is authorized.

DICOMKit review is ongoing. D0–D4 remains deferred for a later separate assignment; do not inspect, build or edit DICOMKit during this release task. No downstream adoption, clinical-conformance claim, new platform validation, direct-main push, auto-merge, branch deletion or tag rewriting is authorized.
