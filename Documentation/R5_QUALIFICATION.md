# R5 qualification and remaining acceptance gates

R5 is in progress on `milestone/r5`, based on accepted R4 merge `d43bc2aaec0c511c6e583dea42dcb57298d8a000` (tree `5dba3e4e84e827e24a3d4745d2a9fd37655608a7`). R4 accepted head `ae654f73f6fc6690b9472436577cac18ecdd4e85` passed all seven required jobs in Actions run `40093317140`: six native host/toolchain combinations and eight Apple SDK targets. Root independently audited those artifacts and the merge tree. R5 reuses unchanged core/CLI/integration security, oracle and performance evidence; no repeat one-hour campaigns or benchmarks are implied.

The version remains `0.1.0-dev.1`. Final R5 acceptance, merge, stable version, tag/release and DICOMKit D0–D4 cutover are not claimed. Locally accepted contents may be published for required remote qualification while external device gates remain open.

## Supported scope and retained evidence

[Frame semantics](R2_FRAME_PROFILE.md), [CLI and bounded peer integration](R3_INTEGRATION.md), [R4 measurements/security](R4_QUALIFICATION.md) and [capabilities](CAPABILITY_MATRIX.md) define actual support. No GPU/SIMD backend or automatic frame concurrency ships. Optimized validated addressing and explicit scalar execution both report scalar CPU. Preferred unavailable acceleration falls back with reporting; required unavailable acceleration fails.

The ordinary Image route is logical-sample preserving, including canonical meaningful-bit alignment/sign extension. Raw allocated-cell decode preserves otherwise-unused high bits as a separate operation. External metadata/ICC/photometric interpretation remains the caller's descriptor responsibility: no DICOM dataset parsing or clinical/display transform occurs. The restricted NRRD pipe profile is full unsigned UInt16 greyscale, not a carrier for signed/12-bit/colour semantics.

All seven common contract files remain byte-identical to their pinned manifest. Apache-2.0 source headers and full inherited DICOMKit MIT notices are preserved. No external core package dependencies, unsafe manifest dependency flags, runtime fetch or external codec fallback are introduced. Synthetic runtime fixtures are deterministic coordinate/component expressions plus independently authored PackBits and DICOM packet vectors, dedicated to CC0; they contain no patient data or third-party dataset. Exact fixture, runner, core and compiled-product hashes accompany execution receipts.

## Target runtime fixture

`Qualification/Runtime/main.swift` is a standalone public-API fixture linked against the unchanged library. `Scripts/qualify-runtime.py` compiles the target library and executable, creates only a uniquely named task-owned simulator, boots it, executes through `simctl spawn`, and shuts down/deletes that exact simulator. It does not download runtimes, deploy physical apps or modify unrelated simulators. Supply a new output directory for every run. Builds are serialized and compilation has no parallel workers.

The fixture executes 42 distinct profile/layout combinations, each with two source-padding variants, independently calculated values and a different destination layout/stride/endian. These cover unsigned/signed mono, unsigned RGB, YBR_FULL and palette-index profiles; 8-bit and 12/16-in-16, planar/interleaved colour, odd 5×3 dimensions, offsets and row padding. It compares scalar/automatic encoded bytes, allocating/caller decode, exact allocation identity, allocation/copy reports and all logical samples. It also exercises four known PackBits vectors, 129-byte row tails and incremental splits, independently authored noncanonical 12-bit DICOM cells (canonical signed/unsigned versus raw routes), every-prefix frame truncation, four resource denial cases, malformed-header preflight reuse, sealed-owner refusal and two concurrent retained-source readers.

Cancellation points are explicit: the encoder cancels from an actual segment-processing callback; the caller-owned decoder provider cancels after the final-buffer fill returns and before sealing/publication. Both must throw `CancellationError`; the decoder's begun destination must remain invalid. This does not claim a deterministic cancellation in the middle of a packet. A delayed inspecting callback independently expires the deadline and must return `resourceLimitExceeded`.

All fixture operations use the explicit Watch admission profile and small allocations, including on Watch. This verifies bounded operations and limit refusal on the tested runtime; it does not stress the Watch maximum capacities or establish a physical-device memory ceiling. Profile defaults remain 16 MiB compressed, 32 MiB decoded/workspace each, at most two workers, 30-second deadline; independent ceilings do not guarantee that their sum fits physical RAM. General defaults and full admission formulas remain in the frame/CLI documents.

Final runner controls bind the executed runner/core/fixture and binary/archive/module hashes before/after, verify SDK/triple/runtime/device compatibility, retain verbose linker and archive-object LC_BUILD_VERSION facts, and compare compiled platform plus actual process simulator UDID/version/build/architecture/OS against the requested runtime. Earlier exact-bound receipts use the preserved earlier runner; later controls are never attributed retroactively. Earlier linker sysroot warnings are retained; independent archive-object/executable platform inspection supplements those receipts. Simulator execution is separate from SDK compilation and physical-device/native gates.

Example repeatable command (using an already installed runtime):

```sh
python3 Scripts/qualify-runtime.py --output /absolute/new-evidence \
  --sdk iphonesimulator --triple arm64-apple-ios26.0-simulator \
  --runtime com.apple.CoreSimulator.SimRuntime.iOS-26-0 \
  --device-type com.apple.CoreSimulator.SimDeviceType.iPhone-17
```

## Platform evidence matrix

| Environment | Executed evidence | Remaining mandatory scope |
|---|---|---|
| macOS arm64, Swift 6.2/6.4 | Accepted R4 native CI on OS 26 runners; local M4/macOS 27.0.1/Swift 6.4 security/performance/oracle evidence | Exact macOS 26.0 runtime qualification remains unavailable locally; runner OS minor/build must be checked |
| Ubuntu 24.04 x86_64/AArch64, Swift 6.2/6.4 | Accepted R4 native six-host matrix includes all four Linux/toolchain combinations, full core/CLI/oracle/integration | R5 exact-head CI after publication |
| macOS Intel x86_64, Swift 6.2/6.4 | CI jobs prepared on `macos-26-intel`; native process/host architecture and absence of translation asserted | Both jobs remain unexecuted until published; label alone is no pass |
| iOS simulator 26.0, iPhone | 42-case fixture passed in actual arm64 process, runtime 26.0 build 23A343 | Representative physical iPhone runtime/device tests |
| iPadOS simulator 26.0 | 42-case fixture passed in actual arm64 process, runtime 26.0 build 23A343 | Representative physical iPad runtime/device tests |
| watchOS simulator 26.0 | 42-case bounded Watch fixture passed in actual arm64 process, runtime 26.0 build 23R353 | Representative physical Watch bounded memory/cancellation/resource qualification |
| tvOS simulator 26.5 | 42-case fixture passed in actual arm64 process, runtime 26.5 build 23L470 | Exact 26.0 runtime and representative physical Apple TV tests |
| visionOS simulator 26.5 | 42-case fixture passed in actual arm64 process, runtime 26.5 build 23O470 | Exact 26.0 runtime and representative physical Vision Pro tests |
| Apple SDK devices/simulators | Accepted R4 eight-target builds at 26.0 deployment floor | Compilation does not satisfy runtime gates |

No physical device was discovered in the local inventory. No simulator, emulation or SDK result substitutes for physical device tests; no unavailable minimum runtime is marked passed. Exact command/exits, compiler/SDK/OS/architecture/device identities and cleanup outcomes are retained in the external completion receipt rather than private machine paths in this repository.

## Clean consumption and CLI/manual installation

`Scripts/qualify-package.py` creates a fresh package whose sole dependency is the public SwiftRLE HTTPS URL at an explicit immutable revision, using isolated scratch/cache paths and no sibling paths. It executes the independent public consumer, verifies the one-pin resolved graph and exact checkout/core hashes, and executes the built consumer directly without a package-manager runtime step. Because core and manifest are unchanged, the R4 merge revision binds the R5 library input without publishing unaudited work.

The same driver uses a hash-bound existing qualified CLI binary, installs it and the matching section-1 manual into a fresh absolute prefix containing spaces/non-ASCII characters, deliberately replaces both with stale bytes, then performs a real update and verifies exact restoration. It executes installed help/version/command help, actual `man -w -M` discovery, manual rendering, binary PackBits pipes and malformed-input exit 3. The unchanged R4 CLI suite retains broader NRRD/frame/exit/cancellation/backpressure/atomic publication coverage. The driver retains all commands, exits, stdout/stderr and input/end hashes. Reuse of a prior successful consumer section requires its exact revision, original runner/input hashes, current checkout/core equality and unchanged built consumer; the final install proof remains separate. The HTTPS/revision consumer at the exact R4 merge passed with one SwiftRLE pin and all current core hashes equal. The persistent install/update/manual/help/pipe checks passed. A first driver assertion did not normalize terminal backspace formatting in rendered manual text; its successful consumer proof is retained and explicitly reused by the corrected driver, with input/checkout/binary hash checks and a fresh direct consumer execution. The failed overall receipt is preserved rather than relabelled passed. Exact executions and hashes are retained in the external completion receipt.

## External environments needed to finish

Provision native macOS Intel runners for both supported Swift toolchains and retain actual host/process architecture, SDK/OS/toolchain identities and exact-head core/CLI results. Provide an exact macOS 26.0 runtime, exact tvOS/visionOS 26.0 runtimes, and representative supported physical iPhone/iPad/Watch/Apple TV/Vision Pro environments with explicit deployment authority. Execute the same representative profile/resource/cancellation/ownership scope (bounded Watch profile), retain target identities and receipts, then independently audit all required exact-head CI and runtime gates. Unavailable hardware remains a blocker to final acceptance, not a waiver.
