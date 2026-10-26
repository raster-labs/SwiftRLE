# Change log

## Unreleased — R5 owner-approved scope qualification, 2026-10-26

- Reconciled documentation, supported profile/backend/resource claims and inherited licence/source/fixture provenance with accepted R0–R4 evidence.
- Added a bounded standalone runtime fixture and exact-input/platform runner for installed simulators, plus native macOS Intel CI alongside both supported toolchains.
- Clean revision consumer and isolated real CLI/manual installation/update qualification are recorded in [R5 qualification](Documentation/R5_QUALIFICATION.md). Qualification work is complete for available native macOS and iPhone/iPad iOS 26 simulators. DEC-11 records the owner waiver of exact macOS 26.0 and physical iPhone/iPad tests as R5 gates; those checks remain UNEXECUTED. Final independent acceptance/exact-final-head CI review/PR #5 merge are tracked separately; no stable tag/release or downstream cutover is claimed.

## Unreleased — R4 accepted optimization and security qualification, 2026-10-24

- Hoisted validated frame addressing for measured nonsingleton cases, retaining the explicit scalar and singleton reference paths with sample/byte parity and direct final ownership.
- Completed controlled final performance, ordinary allocation/copy, predecessor fidelity, independent oracle, ASan/TSan and one-hour-per-surface mutation evidence. Rejected unconditional SIMD repeat scanning; frame scheduling and GPU remain unshipped experiments.
- Independently accepted and merged PR #4 at `d43bc2aa`; accepted-head CI run `40093317140` passed all seven jobs. See [R4 qualification](Documentation/R4_QUALIFICATION.md).

## Unreleased — Milestone R3 CLI and integration, 2026-10-24

- Added dependency-free `swiftrle-cli`, strict attached raw UInt16 NRRD interchange, bounded cancellable/deadline-aware I/O, atomic final-output publication, manual and PREFIX/DESTDIR installer.
- Added separately packaged pinned SwiftJLS real shared-owner transcodes, external DICOMKit candidate adapter, process/pipe/oracle/allocator/mutation gates and six-host CI extensions.
- R2 was accepted and merged through PR #2; R3 was accepted and merged through PR #3 at `a72aa30f`; R4 was subsequently accepted. Current R5 qualification/waiver status is recorded above; final independent acceptance/merge and downstream cutover are separate. See [R3 integration](Documentation/R3_INTEGRATION.md).

## Unreleased — Milestone R1 standalone package, owning API and scalar PackBits, 2026-10-23

- Created standalone `Package.swift` (Swift tools `6.2`, Swift 6 language mode, Apple OS `26.0` deployment floors, zero external dependencies) and independent consumer package (`Examples/Consumer`).
- Implemented the Swift Image Compression Suite common API and owning storage surface in `Sources/SwiftRLE/`: `CodecError`, overflow-checked arithmetic (`checkedAdd`, `checkedMultiply`), `PlaneDescriptor`, `ImageDescriptor` (including `greyscale16`), `StorageWriteLease`, `ReadOnlyImageStorage`, `WritableImageStorage`, `OwnedImageStorage` (`Mutex<State>` + `Atomic<Bool>` reentrancy guard), `Image`, `ImageDestination`, `ResourceLimits` (`general`, `watch`, `default`), `EncodeOptions`, `DecodeOptions`, `RLEProfile`, `RLEFrameDescriptor`, `CodecOptions`, `Encoder`, `Decoder`, `OperationReport` and `CodecCapabilities`.
- Reconciled `DecodeOptions.codecOptions: CodecOptions? = nil` with `DecoderConfiguration.codecOptions` across `inspect(_:options:)`, `decode(_:options:)` and `decode(_:into:options:)`, preserving zero-argument call compatibility while enforcing profile/descriptor conflict checks and explicit R1 rejection of deferred R2 DICOM frame operations (`Encoder.capabilities` and `Decoder.capabilities` report `.contractOnly` in R1).
- Implemented deterministic scalar `PackBitsEncoder` and `PackBitsDecoder` (including `IncrementalSession` / `decodeIncremental`), supporting arbitrary byte streams and row-constrained (`rowBytes * rowCount`) strips, `Int`-widened control-byte arithmetic (`-128` / `0x80` safe), sliced `Data` (`startIndex != 0`), bounded packet/NOP work budgets against `0x80` floods, cancellation/deadline checks and separate output vs workspace accounting.
- Added 25 tests across 4 test suites (`ContractTests.swift`, `OwnershipTests.swift`, `PackBitsTests.swift`, `AuditRegressionTests.swift`) covering common contract validation, `OwnedImageStorage`/`ImageDestination` lifetime invariants, known PackBits vectors, truncated/overrun/NOP-flood limits, incremental chunk splits and two-way interoperability with `libtiff` `4.7.2` (`tiffcp -c packbits`).

- Independent audit repaired deadline conversion traps, aggregate input/output memory admission, incremental failure publication, the greedy encoder expansion bound and deadline checks after callbacks. Added exact-head host/SDK CI gates; see [R1 validation](Documentation/R1_VALIDATION.md) for executed evidence and pending qualification.

## Unreleased — Milestone R0 documentation and baseline foundation, 2026-10-23

- Established the `SwiftRLE` repository foundation under Apache-2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)) while preserving full MIT copyright/permission notices and extraction provenance from `raster-labs/DICOMKit` ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [HISTORY.md](HISTORY.md)). Accepted and published at `main` commit `b778f21cf0619418e739b625e5861d8584d20819`.
- Pinned latest `raster-labs/DICOMKit` `main` at `4b68d7e22829418c88e48dd53d98b25fee50d90d` (`v2.9.0`), reconciled changes against `9bd891660f0dc253871a92576f6f594f05feddb3` and `c0dd2b682a8a921ca72745312d390eae0980dcd3`, and recorded isolated predecessor RLE baseline test receipts in [Documentation/BASELINE_AUDIT.md](Documentation/BASELINE_AUDIT.md).
- Added the seven verified Swift Image Compression Suite common contract specifications and [Documentation/COMMON_CONTRACT_SHA256.txt](Documentation/COMMON_CONTRACT_SHA256.txt), reconciled `0.10.0` policy/CLI vs `0.7.0` companion contract headings, and inventoried reference implementation and independent-consumer call shapes in [Documentation/CONTRACT_INVENTORY.md](Documentation/CONTRACT_INVENTORY.md).
- Recorded the target profile and capability matrix in [Documentation/CAPABILITY_MATRIX.md](Documentation/CAPABILITY_MATRIX.md), owner-approved architecture/licensing/platform/CLI decisions in [Documentation/DECISION_RECORD.md](Documentation/DECISION_RECORD.md), and the R1 implementation handoff in [IMPLEMENTATION.md](IMPLEMENTATION.md).
