# Contributing

Start with [AGENTS.md](AGENTS.md) and [IMPLEMENTATION.md](IMPLEMENTATION.md). R0–R5 are independently accepted and merged; DEC-12 governs the bounded 1.0.0 source-release task. DICOMKit review is separate and D0–D4 remains deferred. Keep changes bounded to the assigned task and preserve standalone package consumption with zero sibling-codec or `DICOMKit` dependencies.

Every behavioural change requires unit and regression tests. Parser, header or ownership changes require matching malformed-input, bounds and `StorageWriteLease` lifetime checks; hot-path or SIMD/concurrency changes require controlled release benchmark evidence ([Documentation/PERFORMANCE.md](Documentation/PERFORMANCE.md)). Changes to common API types require coordinated contract revision across the suite ([Documentation/COMMON_API.md](Documentation/COMMON_API.md)).

Contributions to `SwiftRLE` are licensed under Apache-2.0 ([LICENSE](LICENSE), [NOTICE](NOTICE)) while preserving full MIT copyright and permission notices for code and tests extracted from `DICOMKit` ([THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md), [HISTORY.md](HISTORY.md)). Declare any third-party fixture or development oracle origins and licences; never include clinical/patient health information (PHI), secrets or local user filesystem paths. British English is preferred in prose.
