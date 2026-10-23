# Unit, regression, interoperability and security testing

Contract **0.7.0**. Required evidence for coding agents. Executed Milestone 1 results are recorded separately in each repository; later codec and release gates remain requirements.

## General rules

**TEST-01.** Tests verify independent expected behaviour, not merely duplicate the implementation. Use known vectors, specification invariants, independently generated files, property-based inputs and scalar/accelerated comparisons. A self-round-trip alone can pass when encoder and decoder share a bug. Tests must fail for corrupted output, incorrect precision, copied hand-off buffers and unsafe lifetimes.

Swift Testing or XCTest is acceptable. Preserve valuable predecessor regression tests after auditing assertions and prerequisites. Unit tests and synthetic fixtures run offline and do not require third-party tools. Oracle jobs install pinned independent tools explicitly and report missing tools as missing coverage. A required release oracle gate cannot be satisfied by skipped tests. Do not depend on private patient datasets for normal CI.

Every fixture records source or deterministic generator/seed, redistribution licence, SHA-256, geometry, component roles, storage/meaningful bits, signedness, byte order, expected outcome and expected sample digest or values. Use synthetic or verified de-identified/licensed fixtures. Raw metadata and pixels are not CI log material. A failing generated seed becomes a permanent small regression fixture when safe to retain.

## Required groups

| Group / requirement | Essential cases | Acceptance |
| --- | --- | --- |
| Unit — API-01..13 | Constructors, defaults, mode validation, capability queries, error categories, module-qualified client examples | Same common call shapes and semantics across all four modules |
| Unit — MEM-01..04 | 1x1, odd widths/heights, row padding, offsets, exact/short capacities, misalignment, endianness, planar descriptors, checked-arithmetic boundaries | Valid layouts work; invalid layouts throw before out-of-bounds access |
| Unit — sample meaning | 0/max, alternating extremes, ramps, sparse impulses, all-zero, constant, random, 12-in-16, 16-bit unsigned; supported signed/float extensions | Exact integer values and descriptors, including meaningful bits |
| Unit — parsers | Truncated inputs at every boundary for small fixtures, invalid lengths, entropy tables, markers/boxes, offsets, frame counts and metadata | Defined error; no trap, infinite loop or unchecked allocation |
| Unit — lifecycle | Double writer, read before seal, write after seal, owner released by caller early, decode failure, cancellation, pool reuse, concurrent readers | Owner survives until last user; one deallocation; invalid frames never published |
| Unit — options | Unsupported feature, required/preferred backend, copy-policy mismatch, resource/deadline limit, progress ordering | Clear error or reported fallback; no silent fidelity change |
| Regression | Pinned predecessor corpus and bug reproducers; edge geometries; each advertised mode | No unexplained sample/behaviour regression |
| Interoperability | Independent encoder -> successor decoder and successor encoder -> independent decoder | Correct formats, semantics and declared fidelity |
| Integration | Shared-buffer transcodes and optional adapter harness | No intermediate image file or hand-off copy in required-sharing mode |
| CLI | Exit codes, binary pipes, stderr separation, invalid/malicious headers, cancellation, overwrite rules | Agrees with CLI contract, preserves bytes and errors |
| Platform | Scalar and available accelerated paths on every claimed target | Build and runtime results distinguished; no hidden dependency |

## Milestone 1 acceptance — contract feasibility

Use synthetic sample storage and an adapter experiment to prove the public API and memory contract before codec algorithms are migrated. Compile the agreed call shapes under Swift 6.2 and Swift 6.4 with complete concurrency checking; keep experimental/test-double behaviour distinct from real codec capabilities. An independent consumer must use the local public types without a sibling codec or shared-foundation dependency.

Exercise unsigned full 16-bit and 12-in-16 descriptors, odd dimensions, padded rows, invalid ranges/strides/capacities and checked-arithmetic rejection. Observe synthetic writes followed by sealed reads through the retained owner; test shared allocation identity across adapter wrappers, rejection of overlapping writers, read-before-seal/write-after-seal, early caller release and failure/cancellation cleanup. Run the applicable ownership/race checks on an available supported target and record unavailable gates explicitly.

Record the concrete lease-token signatures and the evidence supporting Sendable/lifetime claims. Mirror any coordinated contract refinement before codec migration. Passing this milestone proves the tested API/storage behaviour only; it does not prove compressed-format interoperability, real-codec throughput or a working transcoder. Those gates follow with the relevant implementation milestones.

## First cross-codec proof — Milestone 3

After the relevant native scalar paths have been migrated and independently validated in Milestone 2, prove their shared-storage integration below. This is not an additional Milestone 1 requirement.

**TEST-02.** Build a development-only harness against SwiftJ2K and SwiftJLS, outside either library's dependency graph. It supplies one owner through each module's adapter wrapper. Use a non-square synthetic image with an odd width, sentinel row padding, both 12-meaningful-bit and 16-meaningful-bit patterns and independently known expected samples.

1. Produce/obtain conformant lossless JPEG 2000 input and validate it with an independent decoder.
2. Inspect with limits, allocate the single destination and record allocation identity/capacity.
3. Decode final samples directly into it; observe writes in the supplied allocation.
4. Pass a sealed read-only view of the same owner into lossless JPEG-LS encoding; observe reads from that allocation.
5. Decode the JPEG-LS output with both the successor decoder and an independent JPEG-LS decoder. Compare every logical sample and declared meaningful precision to the input reference. Compare metadata/interpretation under the preservation policy.
6. Instrument pixel allocations and copy/conversion byte counts over steps 2–4. Permit algorithm workspace with recorded purpose, prohibit an additional full final image for hand-off. Padding sentinels must not be encoded as samples or leak to output.
7. Repeat with cancellation during decode and encode, incompatible layout under require-sharing, explicit allow-copy with reporting, two simultaneous reader encodes, and attempted concurrent mutation.
8. Verify no intermediate image file is opened. A final CLI destination file is distinct from forbidden intermediate image staging. Run the in-process API with file access monitoring where available.

Same-pointer assertions without copy/allocation instrumentation and source-path review are insufficient. A final image copied into the original destination would otherwise produce a false pass.

**TEST-03.** Extend the harness to HTJ2K and each codec pair in both directions where their common capabilities permit. Lossless JPEG means supported lossless JPEG syntax, not baseline lossy JPEG. Signedness mappings require explicit metadata round trips; unsupported pairs must produce the documented error. Test encoded-file semantics, not only RAM flags. Multi-frame/streaming follow with bounded in-flight frames and back-pressure.

## Regression policy

**TEST-04.** Before migration, reproduce the pinned predecessor's useful tests on its compatible platform, record failures and create sample/behaviour baselines. Record exact source revision and configuration. Existing failures are not silently marked acceptable or copied as skips. Resolve them, or document a narrowly scoped excluded capability and its consequence before release.

For lossless modes, sample equality has zero tolerance. Codestream byte equality is required only for promises such as byte-reconstructible JPEG, deterministic encoding at a fixed configuration, or a deliberately pinned unchanged encoding path. New valid encoders need not emit identical bytes to predecessors if sample fidelity, interoperability and size/performance gates pass. For lossy output, record named metrics, colour domain, max error and accepted tolerances before changing kernels. Never loosen a threshold after observing a regression just to pass the build.

Every fixed defect gains a small failing-before/passing-after regression test. Retain malformed-input cases that previously crashed/hung. Compare scalar/accelerated output according to the selected fidelity mode; a generic epsilon is never allowed for lossless integers. Run isolated tests as well as the full suite to expose global-state dependencies and order sensitivity.

## Security and reliability gates

**TEST-05.** Fuzz independent parsers, inspect, decode and descriptor validation with bounded resources. Start from conformant seeds and mutate truncations, lengths, table cardinalities, counts and entropy symbols. Use coverage-guided fuzzing where available; retain seeds and minimised reproducers. Time out hangs and record peak memory. Deterministic parser mutation tests remain mandatory where a fuzzing engine is unavailable. Initial release gate: at least a one-hour fuzz campaign per decode entry point on a supported host, with zero unresolved crashes/hangs/bounds findings; this is a minimum experiment, not a security certification.

Run AddressSanitizer and ThreadSanitizer separately on supported toolchain/target combinations. Exercise any native C/C++ kernels with their applicable undefined-behaviour checks. Record unsupported configurations explicitly; use a supported native host for mandatory ownership/race coverage. Test repeated cancellation, allocation denial, callback re-entrancy, resource exhaustion and backend failure. No unbounded task creation or corrupted successful result is acceptable.

## Resource-limit defaults for implementation trials

**TEST-06.** Establish a finite `ResourceLimits` value in every operation. Initial general profile: compressed input 256 MiB, total published decoded sample bytes 512 MiB, algorithm workspace 512 MiB, 64 million pixels per frame, one million per dimension, 256 frames when using a multi-frame extension, metadata 16 MiB, individual ICC payload 4 MiB, bounded nesting depth 32, worker count at most min(active CPU count, 8), and operation deadline 120 seconds. Strides/padding count towards decoded storage. Bound other attacker-controlled counts by validated format constraints and an explicit parser work budget.

The initial Watch profile reduces compressed input to 16 MiB, decoded storage and workspace to 32 MiB each, workers to 2 and deadline to 30 seconds. These are explicit engineering starting limits, not performance guarantees or validated device memory ceilings. Validate them on target devices and adjust conservatively with a contract revision before release. Applications may set smaller limits. Larger limits require an explicit caller override and remain checked; no input data may raise them.

Limits are independent ceilings, not a guarantee that their sum fits device memory. Account for compressed input, destination, workspace, retained metadata and in-flight operations when admitting work. Before allocation, enforce the application/process memory budget or deny admission; check the monotonic deadline during bounded CPU work. Hardware work needs a finite tested completion timeout and safe lifetime handling. Test inputs just below/at/above every limit. A dimension alone is never a sufficient decompression-bomb defence.

## Evidence and release

**TEST-07.** The coding agent must provide exact executable commands after creating the package, rather than claiming commands ran now. At minimum use debug/release build and test, independent consumer builds, selected sanitizer jobs, fuzz runs, regression runs and release benchmarks. Capture exit codes and machine-readable test reports as well as logs. Validate that test-runner failures cannot be hidden by output filtering or an unrelated CLI entry point.

Evidence records: repository SHA, contract version/hash, fixture and oracle revisions, compiler/SDK/OS/CPU, backend/configuration, commands, counts of passed/failed/skipped tests and reasons, measured memory/copies, benchmark methodology and known limits. No new stable version tag until required correctness, interoperability, platform, security and performance gates are complete. Publish precise supported capabilities, not a broad compliance claim inferred from a test count.

## Native format-pair transcoding gates

**TEST-08.** Add the separately qualified native operations in SwiftJ2K and SwiftJXL without making other codecs depend on them. Their repository-specific TRANSCODING.md files give the source inventory, known gaps, API/CLI requirements and detailed acceptance cases.

For J2K ↔ HTJ2K, test each direction and both round trips with conformant independent fixtures, nonzero textured samples, full 16-bit and 12-in-16 precision. Compare samples and required interpretation exactly with a Part 15-capable oracle where needed. Coefficient paths also verify quantised coefficients and quantisation/transform semantics; sample paths prove the single shared allocation. A nonempty output, matching dimensions or successful all-zero fixture is not a fidelity proof. Decode errors must never become zero-filled success, and predecessor parser-hang skips must become bounded regressions.

For existing lossy JPEG ↔ JPEG XL, compare restored JPEG length and every byte, record SHA-256, and reconstruct with only the JXL available to the operation. Test both independent interoperability directions and actual JXL image decoding. Cover every claimed JPEG/metadata profile; explicitly reject unsupported reconstruction cases. Include missing/corrupt reconstruction metadata, noncanonical padding, expanded-metadata limits and attempts to invoke pixel fallback or supply the original JPEG. Source-based diagnostic reconstruction is not acceptance evidence.

For both operations, verify bounded workspace/copies, cancellation/owner lifetime, source and destination limits, native standalone consumption, and absence of intermediate file or external-process I/O. CLI tests exercise one-process transcode commands, pipes, errors and output publication. Distinguish source inspection, test presence, executed tests and unexecuted coverage. Native transcoder milestones supplement the initial J2K → JPEG-LS shared-image proof; they do not expand Milestone 1 into codec implementation.

## CLI foundation acceptance — contract 0.4.0

Run `Scripts/test-cli.py` against the built executable. Cover help/version/command-local help, JSON capability truth, verbosity levels and aliases, range/usage errors, quiet conflicts, stderr separation, unavailable operations without input/output access, and deterministic closed-pipe errors. Stage installation under a temporary prefix (including spaces), replace a stale manual on update and verify `man -M` discovery plus rendered text. These tests supplement library/Xcode tests and do not prove codec stream interoperability.

## Shared-storage evidence bar — contract 0.6.0

**TEST-09.** A shared-storage claim carries five independent pieces of evidence, and the Milestone 3 spikes showed each one catching something the others missed.

Compare the refactored shipped path against the unmodified predecessor byte for byte, over a corpus that reaches every branch the change touched — both bit widths, both sign conventions, one and several components, packed and padded rows, odd widths, tiled and lossy routes, and any accelerated route that reaches the same stage. Where a library's own suite cannot run on the available host, say so and name the substitute rather than reporting silence as a pass.

On the encode side compare codestreams, not samples. Any difference in what the input stage read changes entropy-coding decisions, so byte identity tests the whole input path at once; sample comparison passed a spike whose shared encode had silently dropped its container wrapper. Change only the caller's row padding and require the codestream to be unchanged, which is the direct test that padding cannot reach the output. On the decode side require exact samples, an allocation identity matching the caller's, caller padding still holding its sentinel, and a round trip that uses a different row stride on each side so a stride cannot be mistaken for the width.

Prove the tests are load-bearing by mutation: make the path ignore the caller's row stride, and make it use the wrong byte order, and record how many expectations fail. A mutation that changes nothing means the evidence is decorative.

Take copy accounting from allocator telemetry in an ordinary build, and state the build. A sanitizer may quarantine freed blocks and report them as live, which makes the same figures meaningless; run the correctness sections under the sanitizers and the accounting sections outside them.

Exercise the ownership rules, not only the happy path: a refused layout leaves a destination reusable, a sealed destination refuses a second writer, concurrent readers of one source agree, and any `@unchecked Sendable` bridge runs under both the thread and address sanitizers. Report the check count, and report failures with the numbers attached.
