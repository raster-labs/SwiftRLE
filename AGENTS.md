# Coding-agent instructions — SwiftRLE

Applies to Antigravity, Claude, Codex and human implementers working in `raster-labs/SwiftRLE`.

## Start here

Read these files in order before starting any assigned milestone:

1. [README.md](README.md), [HISTORY.md](HISTORY.md), this file (`AGENTS.md`) and [IMPLEMENTATION.md](IMPLEMENTATION.md).
2. [Documentation/DECISION_RECORD.md](Documentation/DECISION_RECORD.md), [Documentation/BASELINE_AUDIT.md](Documentation/BASELINE_AUDIT.md), [Documentation/CONTRACT_INVENTORY.md](Documentation/CONTRACT_INVENTORY.md) and [Documentation/CAPABILITY_MATRIX.md](Documentation/CAPABILITY_MATRIX.md).
3. All seven common contract documents in `Documentation/` verified against [Documentation/COMMON_CONTRACT_SHA256.txt](Documentation/COMMON_CONTRACT_SHA256.txt):
   - [Documentation/SUITE_POLICY.md](Documentation/SUITE_POLICY.md) (`0.10.0`)
   - [Documentation/CLI_CONTRACT.md](Documentation/CLI_CONTRACT.md) (`0.10.0`)
   - [Documentation/COMMON_API.md](Documentation/COMMON_API.md) (`0.7.0`)
   - [Documentation/MEMORY_CONTRACT.md](Documentation/MEMORY_CONTRACT.md) (`0.7.0`)
   - [Documentation/PERFORMANCE.md](Documentation/PERFORMANCE.md) (`0.7.0`)
   - [Documentation/PLATFORMS.md](Documentation/PLATFORMS.md) (`0.7.0`)
   - [Documentation/TESTING.md](Documentation/TESTING.md) (`0.7.0`)

`CLAUDE.md` points here and is not a separate policy.

## Precedence and gated milestone workflow

1. **Precedence**: current explicit owner decisions ([Documentation/DECISION_RECORD.md](Documentation/DECISION_RECORD.md)); current common contract (`Documentation/`); RLE-specific architecture and profile rules ([IMPLEMENTATION.md](IMPLEMENTATION.md)); repository workflow guidance.
2. **Delegated development audit**: `SwiftRLE` milestones `R0`–`R5` are executed sequentially, one milestone per fresh chat. Implement only the single milestone explicitly dispatched. Do not self-accept a milestone or start the next milestone before independent engineering audit and formal acceptance.
3. **Milestone branch, pull request & Codex CI review and merge workflow**: Every milestone (`R1`–`R5`) must be developed on a dedicated branch (`milestone/r1`, `milestone/r2`, `milestone/r3`, `milestone/r4`, `milestone/r5`) branched from the latest accepted/merged `main` commit. Do not commit or push directly to `main`, and do not commit or push unaudited milestone work before independent Codex audit and formal acceptance. After Codex accepts a milestone's stable local contents, commit and push the milestone branch and open **one** pull request targeting `main`, then report the PR and CI links for Codex review. The owner explicitly authorises Codex to review all required checks on the exact accepted PR head and merge it into `main`. Antigravity must not merge. Auto-merge, branch deletion and git tags/GitHub releases remain unauthorised. The next milestone begins only after both Codex acceptance and verified Codex merge into `main`.
4. **Downstream `DICOMKit` isolation**: `DICOMKit` (`D0`–`D4`) and all sibling codec repositories (`SwiftJ2K`, `SwiftJLS`, `SwiftJXL`, `SwiftJLI`) are strictly read-only during `SwiftRLE` milestones `R0`–`R5`. Do not modify `DICOMKit` or sibling codec sources, manifests or tags.

## Non-negotiable engineering rules

- **Independence**: `SwiftRLE` core library (`SwiftRLE`) must have zero runtime dependencies on `DICOMKit`, any sibling codec, `CompressionFamily` or `SwiftCompressionFamily`. Do not make platform TIFF encoding the mandatory engine and do not vendor an external reference codec.
- **Naming & CLI**: library/module `SwiftRLE`; executable product `swiftrle-cli`; executable target `SwiftRLECLI`; manual page `ManPages/swiftrle-cli.1` (`CLI_CONTRACT.md` CLI-01).
- **Platform & toolchain**: Swift tools `6.2` minimum (`6.4` primary qualification toolchain), Swift 6 language mode and complete concurrency checking. Apple deployment minima: `macOS 26.0`, `iOS/iPadOS 26.0`, `tvOS 26.0`, `visionOS 26.0` and `watchOS 26.0`. Do not adopt standard-library APIs gated above OS 26.0 (for example `@available(macOS 27, *)` span helpers).
- **Common API & owning storage**: implement the exact common suite types (`Encoder`, `Decoder`, `EncoderConfiguration`, `DecoderConfiguration`, `EncodeOptions`, `DecodeOptions`, `ImageDescriptor`, `PlaneDescriptor`, `Image`, `ImageDestination`, `ReadOnlyImageStorage`, `WritableImageStorage`, `OwnedImageStorage`, `StorageWriteLease`, `ResourceLimits`, `OperationReport`, `CodecCapabilities`, `CodecError`) with async `encode`/`decode` and synchronous `inspect`, plus justified explicit `encodeSynchronously`/`decodeSynchronously` wrappers and `PackBitsEncoder`/`PackBitsDecoder` byte APIs.
- **Direct output & bounded workspace**: allocating decode and caller-storage decode must share the same direct final-output kernel. Never accumulate `[Data]` or `[[UInt8]]` holding all full decoded byte planes. Account for compressed buffers, final pixel allocation and bounded per-row/packet workspace separately.
- **Safety & limits**: validate all untrusted headers, segment offsets, descriptors, strides and counts with checked arithmetic (`addingReportingOverflow`, `multipliedReportingOverflow`) before allocating or shifting. Convert signed PackBits control bytes (`Int8`) to `Int` before negation (`-128` / `0x80` must never overflow). Enforce a bounded packet/control-byte work budget against `0x80` no-op floods. Throw `CodecError` or `CancellationError`; never trap, force-unwrap or exit the process from library code.
- **Sample fidelity**: preserve exact logical samples and required interpretation. No windowing, modality rescale, `MONOCHROME1` inversion, LUT expansion or bit truncation belongs in `SwiftRLE`.
- **Licensing & provenance**: use `// SPDX-License-Identifier: Apache-2.0` on new/adapted `SwiftRLE` source files while preserving `DICOMKit` MIT attribution and provenance in [NOTICE](NOTICE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [HISTORY.md](HISTORY.md). Omit local user filesystem paths and private task history from repository records.

## Required milestone completion report

At the end of each assigned milestone, stop writes and report:
- Exact git `HEAD`, working tree status and SHA-256 hashes of changed/created files.
- Exact build/test commands, exit codes, test counts, skips and toolchain/OS/CPU environment.
- Sample/copy/lifetime/oracle evidence for the milestone's scope.
- Remaining unexecuted, blocked or deferred gates (never mark an unexecuted platform, missing oracle or deferred `DICOMKit` cutover gate as passed).
