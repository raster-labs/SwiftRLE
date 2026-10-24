# Capability, profile and platform inventory — SwiftRLE

Updated24 October2026. R2 is accepted and merged; R3 implements the restricted integration profile below; validation/CI status is recorded in per-revision audit receipts. No release is claimed.

| Surface | Supported profile | Evidence/status |
|---|---|---|
| PackBits bytes/rows | Explicit expected decoded size, optional consistent row geometry, bounded packet work | Accepted R1; preserved R2/R3 library tests |
| DICOM RLE frames | Strict external descriptor;8/16 allocated bits,1..allocated meaningful bits; unsigned/signed mono1/2; unsigned RGB/YBR_FULL planar/interleaved and palette | Accepted R2; canonical/raw-cell distinction in R2_FRAME_PROFILE.md |
| CLI | encode/decode/inspect/validate/capabilities, explicit formats, cancellation/deadline/backpressure, atomic output | R3 implemented profile; per-revision receipts bind qualification; R3_INTEGRATION.md |
| NRRD pipes | Attached raw2D full16 unsigned grey, explicit endian, bounded headers; no12-in-16 semantics | Actual SwiftJLS CLI pipes in both directions; R3 implemented profile; per-revision receipts bind qualification |
| RLE <-> SwiftJLS | Unsigned12/16-in-16 grey, padded rows, either endian, one shared owner; lossless single-scan/no-ancillary/no-mapping/no-restarts JPEG-LS | Separate package pinned0791e54; R3 implemented profile; per-revision receipts bind qualification |
| Other sibling pairs | SwiftJ2K/HTJ2K/SwiftJXL/SwiftJLI | Unavailable/unqualified |
| DICOMKit | External candidate proof only; production D0-D4 deferred | Zero downstream edits/builds |

R2 merge `aa29491f823d0cafdb1d52dc6eb7a22d0e2b92f5`, accepted head `9da84eaf`, exact-head CI run `40069324499`: all seven jobs passed. Six host configurations executed38 debug and38 release tests and27 independent two-way DCMTK profiles per configuration: macOS arm64 Swift6.2/6.4 and Ubuntu24.04 x86_64/aarch64 Swift6.2/6.4. The AppleSDK job compiled eight device/simulator targets; it did not execute device/simulator runtimes. Earlier19-test R1 host evidence is historical and is superseded for current library coverage by the accepted38-test R2 gates.

R3 extends those same six host jobs; its results are bound to per-revision audit receipts. Local R3 checks are recorded in the completion receipt, not inferred from old CI. Native macOS Intel and all unavailable device/simulator runtime gates remain open for R5. Long fuzz/sanitizer/performance qualification remains R4. No signed/colour/metadata peer pair beyond the explicit directional profile is implied.

The seven pinned common contracts remain unchanged. See [R2_FRAME_PROFILE.md](R2_FRAME_PROFILE.md), [R3_INTEGRATION.md](R3_INTEGRATION.md), [DECISION_RECORD.md](DECISION_RECORD.md) and [COMMON_CONTRACT_SHA256.txt](COMMON_CONTRACT_SHA256.txt).
