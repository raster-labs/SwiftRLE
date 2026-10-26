# Capability, profile and platform inventory — SwiftRLE

Updated 26 October 2026. R0–R5 are independently accepted and merged; R5 PR #5 merged at `942dfb9135321bd8b3339fbbdf2388012d72c4b8` after all five required jobs in run `40273685051` and merge-tree verification. Version 1.0.0 is the first stable source-release line; publication status is tracked by GitHub. Exact macOS 26.0 and physical iPhone/iPad tests remain UNEXECUTED and WAIVED_BY_OWNER as R5 gates under DEC-11. Available native macOS/iPhone+iPad iOS 26 simulator evidence defines qualified scope; other-platform evidence is supplemental. See [R5 qualification](R5_QUALIFICATION.md) and [release notes](RELEASE_1_0_0.md).

| Surface | Supported profile | Evidence/status |
|---|---|---|
| PackBits bytes/rows | Explicit expected decoded size, optional consistent row geometry, bounded packet work | Accepted R1–R4; R5 runtime vectors and row tails |
| DICOM RLE frames | Strict external descriptor;8/16 allocated bits,1..allocated meaningful bits; unsigned/signed mono1/2; unsigned RGB/YBR_FULL planar/interleaved and palette | Accepted R2; canonical/raw-cell distinction in R2_FRAME_PROFILE.md |
| CLI | encode/decode/inspect/validate/capabilities, explicit formats, cancellation/deadline/backpressure, atomic output | Accepted R3/R4 profile; per-revision receipts bind qualification; R3_INTEGRATION.md |
| NRRD pipes | Attached raw2D full16 unsigned grey, explicit endian, bounded headers; no12-in-16 semantics | Actual SwiftJLS CLI pipes in both directions; Accepted R3/R4 profile; per-revision receipts bind qualification |
| RLE <-> SwiftJLS | Unsigned12/16-in-16 grey, padded rows, either endian, one shared owner; lossless single-scan/no-ancillary/no-mapping/no-restarts JPEG-LS | Separate package pinned0791e54; Accepted R3/R4 profile; per-revision receipts bind qualification |
| Other sibling pairs | SwiftJ2K/HTJ2K/SwiftJXL/SwiftJLI | Unavailable/unqualified |
| DICOMKit | External candidate proof only; production D0-D4 deferred | Zero downstream edits/builds |

R2 merge `aa29491f823d0cafdb1d52dc6eb7a22d0e2b92f5`, accepted head `9da84eaf`, exact-head CI run `40069324499`: all seven jobs passed. Six host configurations executed38 debug and38 release tests and27 independent two-way DCMTK profiles per configuration: macOS arm64 Swift6.2/6.4 and Ubuntu24.04 x86_64/aarch64 Swift6.2/6.4. The AppleSDK job compiled eight device/simulator targets; it did not execute device/simulator runtimes. Earlier19-test R1 host evidence is historical and is superseded for current library coverage by the accepted38-test R2 gates.

R3 was accepted and merged through PR #3 at `a72aa30f`; its local/CI results are bound to per-revision audit receipts. R4 accepted head `ae654f73` passed all seven required jobs in run `40093317140`; six host configurations each exercised 41 core tests in debug/release plus CLI/oracle/integration coverage. R4 host sanitizer/fuzz/performance qualification is accepted. R5 available macOS/iOS simulator evidence, explicit owner-waived unexecuted checks and exact-final-head CI requirements are distinguished in R5_QUALIFICATION.md. Linux/watchOS/tvOS/visionOS evidence is retained as supplemental under DEC-10; missing further validation there does not block R5. Package targets and codec capabilities are unchanged. No signed/colour/metadata peer pair beyond the explicit directional profile is implied.

The seven pinned common contracts remain unchanged. See [R2_FRAME_PROFILE.md](R2_FRAME_PROFILE.md), [R3_INTEGRATION.md](R3_INTEGRATION.md), [DECISION_RECORD.md](DECISION_RECORD.md) and [COMMON_CONTRACT_SHA256.txt](COMMON_CONTRACT_SHA256.txt).
