# SwiftRLE implementation plan and Milestone R1 handoff

## 1. Approved milestone sequence (`R0`–`R5`) and scope boundary

`SwiftRLE` is implemented across six sequential milestones (`R0`–`R5`), each executed in a separate chat and independently audited before the next milestone begins. Downstream `DICOMKit` integration (`D0`–`D4`) is explicitly **DEFERRED** until `SwiftRLE` is independently qualified.

| Milestone | Deliverable | Exit gate | Status |
| --- | --- | --- | --- |
| **R0** | Repository foundation, latest `DICOMKit` (`4b68d7e2`) & common contract (`0.10.0`/`0.7.0`) pins, read-only source/caller/profile inventory, isolated predecessor RLE test baseline and R1 handoff | Repository identity, source freshness, Apache-2.0/MIT notices, contract SHA-256 verification, baseline test receipt and untouched `DICOMKit` checkout verified by audit | **Local foundation audited; repository access verified; final publication audit pending** |
| **R1** | Standalone `SwiftRLE` package (`Package.swift`), common owning API & storage surface, scalar PackBits byte engine (`PackBitsEncoder`, `PackBitsDecoder`), independent consumer and unit/lifetime/limit tests | PackBits known vectors, `libtiff` oracle, `StorageWriteLease` lifetime, `ResourceLimits` and standalone dependency checks pass | Queued (pending R0 acceptance) |
| **R2** | Strict DICOM RLE frame profile (`RLEFrameDescriptor`, `DICOMRLEHeader`, `DICOMRLEFrame`), direct final-buffer scatter/gather and supported sample/layout matrix | Independent `DCMTK`/`GDCM` interoperability, exact supported 8/16-bit mono/RGB layouts, malformed-input/resource regressions and zero intermediate full-plane allocations pass | Queued |
| **R3** | `swiftrle-cli` executable (`SwiftRLECLI`), `ManPages/swiftrle-cli.1`, installer, separately packaged real cross-codec harness (`RLE <-> JPEG-LS` via `SwiftJLS`) and `DICOMKit`-facing interface proof **outside `DICOMKit`** | Real `SwiftRLE <-> SwiftJLS` shared-storage proof (`16-in-16` and `12-in-16`), CLI contract/pipe/exit tests and external adapter proof pass with zero `DICOMKit` edits | Queued |
| **R4** | Measured SIMD/UMA/concurrency optimisations and optional GPU evaluation | Scalar differential parity, ASan/TSan/lifetime gates and reproducible release benchmark gates pass with zero hidden full-image copies | Queued |
| **R5** | Final documentation, provenance/licence audit, clean URL consumer/install verification and advertised platform/profile qualification | All claims bound to passing evidence; unavailable environments/peers recorded as unexecuted/blocked; no automatic tag/release | Queued |
| **D0–D4** | `DICOMKit` caller baseline lock-in, `RLECodec.swift` adapter cutover, `CompressionManager`/`TransferSyntaxConverter` integration and workload benchmarks | Separately authorised phase after `R5`; **not part of `R0`–`R5`** | **DEFERRED** |

---

## 2. Compact Milestone R1 handoff

### 2.1 Source and contract bindings for R1

- **Extraction source**: `raster-labs/DICOMKit` commit [`4b68d7e22829418c88e48dd53d98b25fee50d90d`](https://github.com/raster-labs/DICOMKit/commit/4b68d7e22829418c88e48dd53d98b25fee50d90d) (`Sources/DICOMCore/RLECodec.swift`, SHA-256 `59f7b00112760ce7b2342546185935dc457f17d6dcc1b4519b43374da18bca43`; `Tests/DICOMCoreTests/RLEEncoderTests.swift`, SHA-256 `0330bfaf229da5e021f8784e8abf10693d8e29e29ba937763f3bdd2ceeb71335`).
- **Common contract**: [Documentation/COMMON_CONTRACT_SHA256.txt](Documentation/COMMON_CONTRACT_SHA256.txt) (`SUITE_POLICY.md` `0.10.0`, `CLI_CONTRACT.md` `0.10.0`, and `COMMON_API.md`, `MEMORY_CONTRACT.md`, `PERFORMANCE.md`, `PLATFORMS.md`, `TESTING.md` `0.7.0`), aligned with reference implementations `raster-labs/SwiftJ2K` @ [`be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`](https://github.com/raster-labs/SwiftJ2K/commit/be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748) and `raster-labs/SwiftJLS` @ [`0791e54a5950bb8082af2218bce3800e03c777b9`](https://github.com/raster-labs/SwiftJLS/commit/0791e54a5950bb8082af2218bce3800e03c777b9).
- **Toolchain & platform settings**: `swift-tools-version: 6.2` minimum (validated on Swift 6.4 primary toolchain), Swift 6 language mode, `.macOS(.v26)`, `.iOS(.v26)`, `.tvOS(.v26)`, `.visionOS(.v26)`, `.watchOS(.v26)`.

### 2.2 Agreed API surface and RLE-specific extensions to implement/investigate in R1

1. **Common Suite Surface (`Sources/SwiftRLE/`)**:
   - Exact common types and call shapes matching `SwiftJ2K`/`SwiftJLS`:
     - `CodecError` (`Category`: `invalidArgument`, `malformedInput`, `unsupportedFormat`, `unsupportedFeature`, `incompatibleImageLayout`, `resourceLimitExceeded`, `storageUnavailable`, `backendUnavailable`, `ioFailure`, `internalFailure`)
     - `SampleType`, `ByteOrder`, `ComponentRole`, `ColourInterpretation`, `AlphaInterpretation`, `PlaneDescriptor`, `ImageDescriptor` (including `ImageDescriptor.greyscale16(width:height:meaningfulBits:rowBytes:offset:limits:)`)
     - `StorageWriteLease`, `ReadOnlyImageStorage`, `WritableImageStorage`, `OwnedImageStorage` (using `Mutex<State>` + `Atomic<Bool>` reentrancy guard for Linux/macOS parity), `ImageMetadata`, `Image`, `ImageDestination` (`allocate`, `write`, `writeUInt16`, `invalidateAfterFailure`)
     - `CompressionMode`, `CopyPolicy`, `MetadataPolicy`, `Backend`, `ExecutionPolicy`, `ResourceLimits` (`general`, `watch`, `default`), `ProgressUpdate`, `EncodeOptions`, `DecodeOptions`
     - `CodecOptions`, `EncoderConfiguration`, `DecoderConfiguration`, `CodecCapabilities`, `CopyEvent`, `Fidelity`, `OperationReport`, `ImageInfo`, `EncodingDescription`, `EncodedImage`, `DecodedImage`, `Encoder`, `Decoder`
2. **RLE-Specific Extensions (`API-13`)**:
   - **Profile selection (`RLEProfile`)**: explicit `.dicomRLEFrame` vs `.packBits` (no format auto-detection from raw bytes).
   - **External frame descriptor (`RLEFrameDescriptor`) & option container reconciliation**:
     - Because a DICOM RLE frame header carries only segment count and byte offsets (no width, height, precision, signedness or colour interpretation), `RLEFrameDescriptor` is mandatory for image `inspect` and `decode`.
     - Reconcile `DecodeOptions.codecOptions.frameDescriptor` (requested in `SwiftRLE` instructions §5.2) with the current suite `DecoderConfiguration.codecOptions` pattern (`SwiftJ2K`/`SwiftJLS`): support `codecOptions: CodecOptions? = nil` on `DecodeOptions` (defaulting to `nil` so standard `decoder.inspect(data)` and `decoder.decode(data)` signatures compile unchanged against `Examples/Consumer`) while resolving `options.codecOptions?.frameDescriptor ?? configuration.codecOptions.frameDescriptor` identically across `inspect(_:options:)`, `decode(_:options:)` and `decode(_:into:options:)`.
   - **Standalone PackBits byte APIs (`PackBitsEncoder`, `PackBitsDecoder`)**:
     - Configure with `EncoderConfiguration` / `DecoderConfiguration` and `EncodeOptions` / `DecodeOptions`.
     - Require explicit `expectedByteCount: Int` on decode and optional row geometry (`rowBytes: Int`, `rowCount: Int` where `rowBytes * rowCount == expectedByteCount`).
     - Return `EncodedBytes(data: Data, report: OperationReport)` and `DecodedBytes(data: Data, consumedByteCount: Int, report: OperationReport)` without inventing 2D image dimensions.
     - Enforce a bounded packet/control-byte work budget (`maximumPacketOperations` derived from `expectedByteCount` and `ResourceLimits`) so `0x80` (`-128`) no-op floods fail with `CodecError(.resourceLimitExceeded, ...)`.
   - **Explicit synchronous convenience wrappers (`API-03`)**:
     - `Encoder.encodeSynchronously(_:options:) throws -> EncodedImage`
     - `Decoder.decodeSynchronously(_:options:) throws -> DecodedImage`
     - `Decoder.decodeSynchronously(_:into:options:) throws -> DecodedImage`
     - Direct synchronous calls into the same validated scalar kernels (never blocking an async task with a semaphore or dispatch group).

### 2.3 Concrete R1 file and test queue

| Planned R1 path | Purpose |
| --- | --- |
| `Package.swift` | SwiftPM manifest (`swift-tools-version: 6.2`, `SwiftRLE` library product/target, `SwiftRLETests` test target; zero external dependencies) |
| `Sources/SwiftRLE/Errors.swift` | `CodecError` and overflow-checked integer arithmetic helpers (`checkedAdd`, `checkedMultiply`) |
| `Sources/SwiftRLE/ImageDescriptor.swift` | `SampleType`, `ByteOrder`, `ComponentRole`, `ColourInterpretation`, `AlphaInterpretation`, `PlaneDescriptor`, `ImageDescriptor` |
| `Sources/SwiftRLE/ImageStorage.swift` | `StorageWriteLease`, `ReadOnlyImageStorage`, `WritableImageStorage`, `OwnedImageStorage` |
| `Sources/SwiftRLE/Image.swift` | `ImageMetadata`, `Image`, `ImageDestination` and alignment-safe byte-order sample accessors |
| `Sources/SwiftRLE/Options.swift` | `CompressionMode`, `CopyPolicy`, `MetadataPolicy`, `Backend`, `ExecutionPolicy`, `ResourceLimits`, `ProgressUpdate`, `EncodeOptions`, `DecodeOptions` |
| `Sources/SwiftRLE/Telemetry.swift` | Atomic pixel allocation and copy-event telemetry counters for test verification |
| `Sources/SwiftRLE/RLEDescriptor.swift` | `RLEProfile`, `RLEFrameDescriptor` and `CodecOptions` |
| `Sources/SwiftRLE/PackBitsEncoder.swift` | Deterministic scalar PackBits byte and row-constrained encoder (`EncodedBytes`) with checked worst-case expansion bounds |
| `Sources/SwiftRLE/PackBitsDecoder.swift` | Strict scalar and incremental PackBits decoder (`DecodedBytes`) with `Int`-widened control arithmetic, sliced-`Data` safety and NOP work budget |
| `Sources/SwiftRLE/CodecAPI.swift` | `Encoder`, `Decoder`, `EncoderConfiguration`, `DecoderConfiguration`, `CodecCapabilities`, `OperationReport`, `ImageInfo`, `EncodedImage`, `DecodedImage` |
| `Tests/SwiftRLETests/ContractTests.swift` | Descriptor validation, `ResourceLimits`, `Encoder`/`Decoder` configuration and capability checks |
| `Tests/SwiftRLETests/OwnershipTests.swift` | `OwnedImageStorage` & `ImageDestination` lifecycle: preflight reuse, begun-write invalidation, double writer, stale/foreign token, reentrant borrow, concurrent readers, single release and cancellation |
| `Tests/SwiftRLETests/PackBitsTests.swift` | Known vectors (`02 41 42 43` -> `"ABC"`, `FF 7F` -> `2x 0x7F`, `81 00` -> `128x 0x00`, `80` -> NOP, empty, run lengths `1/2/3/127/128/129`, row boundaries, truncation at every position, overshoot/underrun, `0x80` flood budget, incremental chunk splits, sliced `Data`, and `libtiff` `tiffcp -c packbits` oracle interoperability) |
| `Examples/Consumer/Package.swift` & `Sources/Consumer/main.swift` | Standalone package consumer compiling and exercising `SwiftRLE` public API and PackBits byte operations |

### 2.4 Remaining gates across R2–R5 (not claimed in R0 or R1)

- **R2**: DICOM 64-byte header & 1..15 segment profile, direct strided byte-lane scatter/gather, `8/16`-bit unsigned/signed mono & unsigned RGB/YBR/palette profiles, canonical `12-in-16` unused-bit normalization vs raw cell preservation, `DCMTK` (`dcmdrle`/`dcmcrle`) and `GDCM` (`gdcmconv`) interoperability.
- **R3**: `swiftrle-cli` (`SwiftRLECLI`), `ManPages/swiftrle-cli.1`, staged installer, NRRD/raw pipe tests, real `SwiftRLE <-> SwiftJLS` shared-storage transcoding harness, and external `DICOMKit`-facing adapter proof.
- **R4**: Measured SIMD/UMA/parallel optimisations, ASan/TSan runs, >= 1 hour fuzzing per decode entry point and release performance benchmarks.
- **R5**: Multi-platform build/runtime matrix (Apple OS 26 targets + Linux Ubuntu 24.04 `aarch64`/`x86_64`), clean URL consumer verification and release readiness audit.
