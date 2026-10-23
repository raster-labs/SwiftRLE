# Change log

## Unreleased — Milestone R0 documentation and baseline foundation, 2026-10-23

- Established the `SwiftRLE` repository foundation under Apache-2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)) while preserving full MIT copyright/permission notices and extraction provenance from `raster-labs/DICOMKit` ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [HISTORY.md](HISTORY.md)).
- Pinned latest `raster-labs/DICOMKit` `main` at `4b68d7e22829418c88e48dd53d98b25fee50d90d` (`v2.9.0`), reconciled changes against `9bd891660f0dc253871a92576f6f594f05feddb3` and `c0dd2b682a8a921ca72745312d390eae0980dcd3`, and recorded isolated predecessor RLE baseline test receipts in [Documentation/BASELINE_AUDIT.md](Documentation/BASELINE_AUDIT.md).
- Added the seven verified Swift Image Compression Suite common contract specifications and [Documentation/COMMON_CONTRACT_SHA256.txt](Documentation/COMMON_CONTRACT_SHA256.txt), reconciled `0.10.0` policy/CLI vs `0.7.0` companion contract headings, and inventoried reference implementation and independent-consumer call shapes in [Documentation/CONTRACT_INVENTORY.md](Documentation/CONTRACT_INVENTORY.md).
- Recorded the target profile and capability matrix in [Documentation/CAPABILITY_MATRIX.md](Documentation/CAPABILITY_MATRIX.md), owner-approved architecture/licensing/platform/CLI decisions in [Documentation/DECISION_RECORD.md](Documentation/DECISION_RECORD.md), and the R1 implementation handoff in [IMPLEMENTATION.md](IMPLEMENTATION.md).
- No `Package.swift`, library source code, CLI binary, test target or release tag is included in Milestone R0.
