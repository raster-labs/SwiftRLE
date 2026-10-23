# Milestone R0 — Predecessor source baseline, caller inventory and executed test audit

**Date**: 23 October 2026  
**Milestone**: `R0` (Repository foundation, source/contract pin, read-only inventory and baseline test execution)  
**Pinned Predecessor Repository**: [`https://github.com/raster-labs/DICOMKit.git`](https://github.com/raster-labs/DICOMKit)  
**Pinned `main` Commit SHA**: [`4b68d7e22829418c88e48dd53d98b25fee50d90d`](https://github.com/raster-labs/DICOMKit/commit/4b68d7e22829418c88e48dd53d98b25fee50d90d) (`v2.9.0`, `2026-10-23T13:45:06+05:30`, `"Prepare DICOMKit v2.9.0 release"`)

---

## 1. Source identity and three-revision comparison (`c0dd2b68` vs `9bd89166` vs `4b68d7e2`)

Remote `refs/heads/main` and `HEAD` of `https://github.com/raster-labs/DICOMKit.git` were verified at `2026-10-23T09:04:20Z` and pinned at `4b68d7e22829418c88e48dd53d98b25fee50d90d`.

| Revision role | Commit SHA | Commit timestamp | Subject | Relationship to RLE extraction files |
| --- | --- | --- | --- | --- |
| September handoff baseline | [`c0dd2b682a8a921ca72745312d390eae0980dcd3`](https://github.com/raster-labs/DICOMKit/commit/c0dd2b682a8a921ca72745312d390eae0980dcd3) | `2026-09-17T14:37:42+05:30` | `Merge pull request #211 from Raster-Lab/feature/mwl-datetime-range-and-vl-modalities` | Historical baseline inspected by the September 2026 handoff instructions (`swift-tools-version: 6.2`; predates 25 Sept 2026 RLE row-boundary and strict segment-length fixes). |
| Reviewed local branch snapshot | [`9bd891660f0dc253871a92576f6f594f05feddb3`](https://github.com/raster-labs/DICOMKit/commit/9bd891660f0dc253871a92576f6f594f05feddb3) | `2026-10-23T12:04:33+05:30` | `Fix dicom-mpps N-CREATE worklist linking and N-SET update compatibility` | Contains all RLE, codec and manifest updates (`swift-tools-version: 6.4`). **Zero diff** on RLE/codec/manifest files relative to `4b68d7e2`. |
| **Pinned R0 freeze (`main` / `v2.9.0`)** | [`4b68d7e22829418c88e48dd53d98b25fee50d90d`](https://github.com/raster-labs/DICOMKit/commit/4b68d7e22829418c88e48dd53d98b25fee50d90d) | `2026-10-23T13:45:06+05:30` | `Prepare DICOMKit v2.9.0 release` | Merges `#230` (`cb1dd248`) and bumps version metadata in `CHANGELOG.md`, `README.md`, `Sources/DICOMKit/DICOMKit.swift` and `Tests/DICOMKitTests/DICOMFileTests.swift` (4 files, `+9/-3` lines; zero RLE changes vs `9bd89166`). |

### 1.1 Exact SHA-256 hashes of extraction and caller paths

| Repository-relative path in `DICOMKit` | SHA-256 at `c0dd2b68` (handoff) | SHA-256 at `9bd89166` & `4b68d7e2` (pinned `main`) | Bytes (`4b68d7e2`) | Lines (`4b68d7e2`) | Diff (`c0dd2b68..4b68d7e2`) |
| --- | --- | --- | --- | --- | --- |
| `Sources/DICOMCore/RLECodec.swift` | `e37b1311c5109bc5e9fae8f0484787539617f5e0bc093f3785c3335e9ef6192a` | `59f7b00112760ce7b2342546185935dc457f17d6dcc1b4519b43374da18bca43` | 20,738 | 438 | `86 +-` (row-boundary encode + strict decode checks) |
| `Tests/DICOMCoreTests/RLEEncoderTests.swift` | `7fc16ccf9ddcad2421f63bacd65e8e89cc799f98cc9998651b845ace2891ac5f` | `0330bfaf229da5e021f8784e8abf10693d8e29e29ba937763f3bdd2ceeb71335` | 11,949 | 263 | `+119` (`RLECodecStrictDecodingTests`, `RLEEncoderRowBoundaryTests`) |
| `Tests/DICOMCoreTests/CompressedPixelDataTests.swift` | `87d1599cd207b1439bbfef43ef218b8d2f126ec5d2152e06d3c983a474e1e4a8` | `87d1599cd207b1439bbfef43ef218b8d2f126ec5d2152e06d3c983a474e1e4a8` | 16,350 | 514 | Unchanged |
| `Tests/DICOMCoreTests/CodecFuzzTests.swift` | `9beeefd013b45370cdf6e3781e8f13cead49513d1c81717d7a2a03506b60772a` | `9beeefd013b45370cdf6e3781e8f13cead49513d1c81717d7a2a03506b60772a` | 7,873 | 174 | Unchanged |
| `Sources/DICOMCore/ImageCodec.swift` | `266fd19d09ce26721c320ebbf2ebd0e170f3aa9f22a989bf25799052608cdb30` | `a594e77140f6ff441af4467a4edf798fcf997ded6e4e79326e7ec655e4edc215` | 20,986 | 512 | `35 +-` |
| `Sources/DICOMCore/PixelDataDescriptor.swift` | `51e0f61030de6e845ff6b3b92f925a46b48a8bdbec1c48645f448694b30d8796` | `f84f39a65615459e8eeee426578a8f8b64ee62fdd4a6c8053d3e30a16402386c` | 7,184 | 192 | `60 +-` |
| `Sources/DICOMCore/PixelInterleaveSupport.swift` | `5f0f13b44a061abfd3abd70e399ce455d50b9facd8db3baa25430d375f8a0017` | `b2ed2b0868695383d02313b164804692225e1d042e3a1edcf9b774d75cefe230` | 2,656 | 60 | `+2` |
| `Sources/DICOMKit/Compression/CompressionManager.swift` | `0c47c9ae13899ee195a480254fdd0ab3ab597fce84c97cd3b29fba33039f9d10` | `eac2917b07a5540d781b36f90c1b9a36ddcec6a46e08cbb8245f3d4ee2a37410` | 64,774 | 1,281 | `157 +-` |
| `Sources/DICOMCore/TransferSyntaxConverter.swift` | `b8a34d97e1dd773d5d81796d63286ee75abf73dcf487a1cbde9683da557865ac` | `8a6d487941e538a11e477e1c7e29902fe40b83feca95550cf4560da229af82a2` | 83,372 | 1,835 | `321 +-` |
| `Sources/DICOMKit/DICOMFile+FrameAccess.swift` | `014e95e270a452b5048286df31d28d5f3aa97123860d36a37ff9d81606b2c14b` | `37f3cfa285f11e17a20e8408ead41096126411c036c6a67eab64fe5d4f759b98` | 10,846 | 228 | `27 +-` |
| `Package.swift` | `5a6851a2819c313985ab14f7d7645078b2b1073a88b8e9b147696699c702fec6` | `7f39fc12046a6bb85b5e40b6bd3f05d4702fc119a429d06c02132de35e5059e2` | 66,473 | 1,501 | `543 +-` (`swift-tools-version: 6.4`; expanded CLI test targets) |
| `Package.resolved` | *(absent at `c0dd2b68`)* | `f42c82a74f4a24ff353f3d8c5df4e9893f11dab9514bdd6e57335dd105eb5500` | 1,759 | 60 | Added (`J2KSwift` `11.0.3`, `JLSwift` `0.10.1`, `JLISwift` `0.6.0`, `JXLSwift` `1.4.0`, `CompressionFamily` `1.0.0`, `swift-argument-parser` `1.8.2`) |
| `LICENSE` | `4c0768004e1c88e30b7c28f3f4ea03998c351c89b81db0d05e333998acf8b9f4` | `4c0768004e1c88e30b7c28f3f4ea03998c351c89b81db0d05e333998acf8b9f4` | 1,070 | 21 | Unchanged (MIT, `Copyright (c) 2026 rasterdevapps`) |

---

## 2. Read-only source inventory (`4b68d7e22829418c88e48dd53d98b25fee50d90d`)

*Note: All items in Section 2 are read-only source inspection findings, kept strictly separate from the executed test evidence in Section 3.*

### 2.1 RLE kernels and helpers at the pinned source

The following names and declaration lines refer to [RLECodec.swift at the pinned commit](https://github.com/raster-labs/DICOMKit/blob/4b68d7e22829418c88e48dd53d98b25fee50d90d/Sources/DICOMCore/RLECodec.swift), not proposed SwiftRLE helpers.

| Symbol / declaration line | Current behaviour and extraction notes |
| --- | --- |
| `RLECodec` (13) | `public struct RLECodec: ImageCodec, ImageEncoder, Sendable`; synchronous DICOM facade. |
| `decodeFrame(_:descriptor:frameIndex:) throws -> Data` (33) | Parses the header and decodes each segment directly in this method, accumulating `[Data]`, then calls the allocating `interleaveSegments(_:descriptor:)`. It does **not** call `decodeSegments`. |
| `decodeFrame(_:descriptor:frameIndex:into:) throws -> Int` (95) | Checks destination capacity and a non-nil base address, calls `decodeSegments`, then the pointer overload `interleaveSegments(_:descriptor:into:capacity:)`; returns `bytesPerFrame`. Full intermediate decoded byte planes remain allocated. |
| `decodeSegments(_:descriptor:) throws -> [Data]` (115) | Shared with the caller-buffer entry point. Checks segment count, expected count and `segmentStart < segmentEnd && segmentEnd <= frameData.count`; rebases subdata ranges with `frameData.startIndex`. |
| `interleaveSegments(_:descriptor:into:capacity:)` (151) | Scatters already-decoded byte planes into the caller pointer. This is an overload named `interleaveSegments`, not a separate `interleaveSegmentsIntoBuffer` function. |
| `canEncode(with:descriptor:) -> Bool` (191) | Checks 8/16 allocated bits and segment count in `1...15`; does not validate geometry, meaningful precision or compression configuration. |
| `encodeFrame(_:descriptor:frameIndex:configuration:) throws -> Data` (205) | Calls `deinterleaveSegments(_:descriptor:numberOfSegments:)`, encodes each plane row by row, appends zero padding to odd-length compressed segments, and assembles the 64-byte header and segments inline. There is no `assembleRLEFrame` helper. |
| `deinterleaveSegments(_:descriptor:numberOfSegments:) -> [[UInt8]]` (239) | Copies `[UInt8](frameData)` and allocates every full byte plane; substitutes zero for input offsets beyond the input count (260). |
| `encodeRLESegment(_:rowLength:) -> Data` (274) | Reserves `src.count / 2 + 16`, splits into rows using `max(1, rowLength)`, invokes `encodeRLERun`, and returns `Data(out)`. Segment padding is performed by `encodeFrame`, not here. |
| `encodeRLERun(_:from:to:into:)` (288) | Uses repeat packets for runs of **at least 2** identical bytes, capped at 128. Literal packets stop before the next repeat pair, row end or 128 bytes. |
| `writeUInt32LE(_:into:at:)` (316) | Static helper writes the header's little-endian 32-bit fields. |
| `decodeRLESegment(_:expectedLength:) throws -> Data` (332) | Reads its `Data` directly; there is no `[UInt8](data)` copy. Rejects premature end and decoded-length overshoot. Handles `-128` before the repeat branch; repeat count is `Int(-controlByte) + 1`, so the current code negates only `-127...-1`. Allows at most one trailing byte, without validating its value or parity. |
| `interleaveSegments(_:descriptor:) -> Data` (395) | Allocates the final output and reconstructs little-endian samples from MSB-first byte planes in planar/interleaved order. |

### 2.2 Relevant caller and test inventory

| Category | DICOMKit path | Observed role |
| --- | --- | --- |
| Protocols and registry | `Sources/DICOMCore/ImageCodec.swift` | Synchronous `ImageCodec`/`ImageEncoder`; one `RLECodec` registered for both directions at lines 430–436. |
| Descriptor | `Sources/DICOMCore/PixelDataDescriptor.swift` | Geometry, allocated/stored bits, high bit, signedness, photometric interpretation, planar configuration and size/bit helpers. Remains in DICOMKit. |
| Adjacent layout helpers | `Sources/DICOMCore/PixelInterleaveSupport.swift` | `interleavedFrameBytes(from:descriptor:)` and `dicomFrameBytes(fromInterleaved:descriptor:)`; not called by RLECodec. |
| Transfer syntax and conversion | `Sources/DICOMCore/TransferSyntax.swift`, `TransferSyntaxConverter.swift` | RLE Lossless UID `1.2.840.10008.1.2.5`; conversion policies include RLE, with registry-based codec dispatch and encapsulated offset-table assembly. |
| Frame access | `Sources/DICOMKit/DICOMFile+FrameAccess.swift` | Calls the caller-buffer `decodeFrame` into `AlignedPixelBuffer`. |
| Frame extraction/concurrency | `Sources/DICOMKit/DICOMFile+PixelData.swift`, `DICOMFile+ParallelDecode.swift` | Pixel/frame access and parallel decode context; outside the extraction. |
| Compression/conversion facade | `Sources/DICOMKit/Compression/CompressionManager.swift`, `DICOMConverter.swift`, `ConversionDiagnostics.swift` | RLE selection and conversion diagnostics remain in DICOMKit. |
| CLI callers | `Sources/dicom-compress/main.swift`, `Sources/dicom-convert/main.swift` | Compression/transfer-syntax command entry points; no changes in this phase. |
| Core tests | `Tests/DICOMCoreTests/RLEEncoderTests.swift`, `CompressedPixelDataTests.swift`, `CodecFuzzTests.swift`, `TransferSyntaxConverterTests.swift` | Round trips, strict decode, row boundaries, registry, sliced input, caller-buffer and malformed-input cases. Executed selection is listed in Section 3. |
| Integration tests | `Tests/DICOMKitTests/FrameAccessTests.swift`, `DICOMConverterTests.swift`, `PixelEditorTests.swift`, `PixelCleaningWorkflowTests.swift` | Downstream coverage inspected but not executed for this R0 receipt. FrameAccessTests includes `testAlignedSelectedFrameMatchesUnalignedRLE`, `testCallerOwnedRLEDecodeWritesDirectly`, and `testProgressiveDecodeFallsBackToSingleFinalForRLE`. |
| Tool/corpus tests | `Tests/dicom-compressTests/`, `Tests/DICOMRoundTripTest/` | Further downstream checks; not executed in R0. |

### 2.3 Fixes to preserve and remaining extraction work

| Observation at pinned source | Required SwiftRLE treatment |
| --- | --- |
| Encoder already stops PackBits packets at row boundaries (274–314). Strict decoder rejects short output and overshoot (332–386). | Preserve these fixes and their regression tests; they postdate the September handoff. |
| Both decode variants allocate all decoded byte planes. Encode copies input and allocates all raw planes plus compressed segments. | R2 must use direct final-buffer scatter/gather or bounded row workspace; the present caller-buffer facade does not prove copy-free decoding. |
| Encoder substitutes zero for missing input bytes (260); `canEncode` does not validate source capacity or full descriptors. | Validate capacity and checked descriptor arithmetic before access; reject short input and unsupported compression modes. |
| Header validation does not enforce first offset 64, unused zero slots or the complete segment-padding rules. Decoding limits output by whole segment, not individual row boundaries. | R2 must validate the full selected DICOM profile and row constraints. |
| Decoder accepts any single trailing byte and has no explicit packet/control-byte work budget. | Specify generic PackBits versus DICOM trailing-byte/no-op policies separately; enforce bounded work and strict DICOM padding. |
| `-128` is guarded before negation in the predecessor, but repeat arithmetic remains in `Int8` until conversion. | Preserve no-op handling; use widened integer arithmetic in the standalone engine. Do not describe the existing guarded branch as an observed overflow. |
| Descriptor products/shifts are not uniformly checked. | Validate all geometry, precision, counts, strides and ranges with checked arithmetic in SwiftRLE. Any later DICOMKit hardening remains deferred. |

---

## 3. Executed predecessor baseline test evidence (`4b68d7e22829418c88e48dd53d98b25fee50d90d`)

An immutable archive snapshot of `raster-labs/DICOMKit` at `4b68d7e22829418c88e48dd53d98b25fee50d90d` was extracted into an isolated baseline workspace outside the protected `DICOMKit` checkout. Zero source, manifest or test files were modified.

### 3.1 Execution environment and snapshot metrics

| Property | Value |
| --- | --- |
| Snapshot commit | `4b68d7e22829418c88e48dd53d98b25fee50d90d` |
| Snapshot file counts | `988` `.swift` files under `Sources/`, `794` `.swift` files under `Tests/` |
| Swift compiler | `Apple Swift version 6.4 (swiftlang-6.4.0.34.1 clang-2100.3.34.1)`, target `arm64-apple-macosx27.0.0` |
| Xcode / macOS SDK | `Xcode 27.0` (`Build version 27A266a`), `MacOSX27.0.sdk` |
| Host OS & CPU | `macOS 27.0.1` (`26A434`), `Darwin 27.0.0 arm64`, `Apple M4` (10 cores, 16 GiB RAM) |

### 3.2 Executed command and result summary

Using the repository-supported `--test-product DICOMCoreTests` selection from `.github/scripts/run-focused-tests.sh` with an RLE-specific filter:

```bash
swift test -Xswiftc -Xfrontend -Xswiftc -enable-cross-import-overlays \
  --scratch-path .build -c debug --test-product DICOMCoreTests --no-parallel \
  --filter 'RLEEncoderTests|RLECodecStrictDecodingTests|RLEEncoderRowBoundaryTests|RLECodecTests|CompressedTransferSyntaxTests/testRLELossless|CodecRegistryTests/testHasRLECodec|CodecRegistryTests/testSupportedTransferSyntaxes|CodecRegistryEncoderTests/testRLEEncoderAvailable|CodecFuzzTests/testRLE'
```

- **Exit code**: `0`
- **Build time**: `55.97 s` (`DICOMCoreTests-product` debug build)
- **XCTest execution (`DICOMCoreTests.xctest` -> `CodecFuzzTests`)**: **5 tests executed, 5 passed, 0 failures, 0 skipped** (`0.018 s`):
  1. `-[DICOMCoreTests.CodecFuzzTests testRLEAdversarialSegmentOffsets]` — passed (`0.002 s`)
  2. `-[DICOMCoreTests.CodecFuzzTests testRLECallerOwnedDecodeIsIndependentOfSliceStartIndex]` — passed (`0.000 s`)
  3. `-[DICOMCoreTests.CodecFuzzTests testRLEDecodeIsIndependentOfSliceStartIndex]` — passed (`0.000 s`)
  4. `-[DICOMCoreTests.CodecFuzzTests testRLEDecoderSurvivesRandomByteMutations]` — passed (`0.009 s`)
  5. `-[DICOMCoreTests.CodecFuzzTests testRLETruncationAtEveryLength]` — passed (`0.000 s`)
- **Swift Testing execution (`Testing Library Version: 2084`)**: **25 tests in 8 suites executed, 25 passed, 0 failures, 0 skipped** (`0.007 s`):
  - `RLECodec Tests` (5 tests: `testSupportedTransferSyntaxes`, `testRLEDecodeLiteralRun`, `testRLEDecodeRepeatRun`, `testRLEDecodeEmptyData`, `testRLEDecodeDataTooShort`)
  - `Compressed TransferSyntax Tests` (1 test: `testRLELossless`)
  - `CodecRegistry Tests` (2 tests: `testHasRLECodec`, `testSupportedTransferSyntaxes`)
  - `JPEG-LS CodecRegistry Tests` (1 test: `testSupportedTransferSyntaxes`, matched by substring filter)
  - `RLE Encoder Tests` (9 tests: `testSupportedEncodingTransferSyntaxes`, `testCanEncode`, `testRegistryHasEncoder`, `testRoundTrip8BitGray`, `testRoundTrip16BitGray`, `testRoundTripRGBInterleaved`, `testRoundTripRGBPlanar`, `testRoundTripConstantFrame`, `testRoundTripMultiframe`)
  - `RLECodec strict segment decoding` (4 tests: `testWellFormed`, `testShortSegmentThrows`, `testOvershootThrows`, `testTrailingBytesThrow`)
  - `RLE encoder row boundaries (PS3.5 2026a G.3.1)` (2 tests: `testRunsDoNotCrossRows`, `testLiteralRunsDoNotCrossRows`)
  - `CodecRegistry Encoder Tests` (1 test: `testRLEEncoderAvailable`)
- **Total executed predecessor tests**: **30 tests** (29 RLE-specific + 1 substring-matched registry test), **30 passed, 0 failed, 0 skipped**.


### 3.3 Independent audit reproduction

Codex compared 1,862 source, test and manifest files in the isolated snapshot against Git blobs at the pinned commit: zero mismatches. The same selection was independently re-executed with `--skip-build` on the retained build: exit 0, 5 XCTest cases plus 25 Swift Testing cases, zero failures. This verifies the predecessor baseline only, not SwiftRLE implementation or platform qualification. Detailed local logs and the original submission are retained separately from public repository records.
