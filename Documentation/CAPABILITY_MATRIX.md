# Capability, profile and platform inventory — SwiftRLE

**Date**: 23 October 2026  
**Milestone**: `R1` (updated from accepted `R0` commit `b778f21cf0619418e739b625e5861d8584d20819`)
**Current Implementation Status**: **Milestone R1 implements the standalone `SwiftRLE` package, common suite API & owning storage surface (`OwnedImageStorage`, `StorageWriteLease`, `Image`, `ImageDestination`), and the deterministic scalar `PackBitsEncoder`/`PackBitsDecoder` byte engine (verified against known vectors and `libtiff` `4.7.2` on macOS Apple Silicon).** The `Image`-level `Encoder` and `Decoder` report `CodecCapabilities.contractOnly` (`canEncode == false`, `canDecode == false`, `canInspect == false`) in `R1` and explicitly reject deferred `R2` DICOM RLE frame operations. No non-host platforms (`iOS`, `tvOS`, `visionOS`, `watchOS`, native Intel `macOS`, `Linux`) or cross-codec pairs (`R3`–`R5`) are claimed as qualified in `R1`.

---

## 1. Format and sample profile matrix

| Profile / layer | Storage bits | Meaningful bits | Sample type | Components & colour semantics | RAM layout (`ImageDescriptor` / `PlaneDescriptor`) | Compressed RLE layout | Predecessor `DICOMKit` (`4b68d7e2`) status | `SwiftRLE` milestone & status |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| **Generic PackBits bytes** | Byte stream (`8`-bit bytes) | N/A (arbitrary byte sequence) | Byte identity | Arbitrary byte buffer (`0...maximumDecodedBytes`) | Contiguous or sliced `Data` (`startIndex != 0`) | Raw PackBits control/payload packets; no 64-byte header or automatic even-byte pad | Internal helper only (`encodeRLERun` / `decodeRLESegment` inside DICOM frame codec) | **R1 — Implemented & verified** (`PackBitsEncoder`, `PackBitsDecoder`, `decodeIncremental`, known vectors + `libtiff` `4.7.2` `tiffcp -c packbits` oracle) |
| **Row-constrained PackBits** | Byte stream (`rowBytes * rowCount`) | N/A | Byte identity | Explicit `rowBytes > 0`, `rowCount > 0` | Contiguous consecutive rows or a sliced byte buffer | Independent PackBits runs per row (no run crosses `rowBytes`) | Internal helper (`encodeRLESegment(_:rowLength:)`) | **R1 — Implemented & verified** (row-boundary vectors + `libtiff` `4.7.2` two-way strip oracle) |
| **Shared-memory proof profile (`MEM-03`)** | `16` | `16` and `12` (`12-in-16`) | `.unsignedInteger` | `1` (`.grey`, `.greyscale`) | Single plane, little-endian, `sampleStride == 2`, `pixelStride == 2`, even `rowBytes >= width * 2`, optional nonzero `offset` | 64-byte header + `2` segments (`MSB` plane 0, `LSB` plane 1) | `16-in-16` tested (`testRoundTrip16BitGray`); allocates intermediate `[Data]` planes | **R1 — Storage & descriptor implemented** (`ImageDescriptor.greyscale16`, `OwnedImageStorage`, `ImageDestination`); **R2** (direct scatter/gather + `DCMTK`/`GDCM` oracle) & **R3** (`SwiftRLE <-> SwiftJLS` shared storage) queued |
| **DICOM 8-bit monochrome** | `8` | `1...8` (canonical `8`) | `.unsignedInteger`, `.signedInteger` | `1` (`.grey`: `MONOCHROME1`, `MONOCHROME2`) | Single plane, `sampleStride == 1`, `pixelStride >= 1`, `rowBytes >= width`, optional `offset` | 64-byte header + `1` segment | Unsigned 8-bit tested (`testRoundTrip8BitGray`, `RLECodecTests`); signed not separately verified | **R2** — separate unsigned & signed qualification (`-128...127`, `0...255`) + `DCMTK`/`GDCM` |
| **DICOM 16-bit monochrome (unsigned & signed)** | `16` | `1...16` (specifically `12` and `16`) | `.unsignedInteger`, `.signedInteger` | `1` (`.grey`: `MONOCHROME1`, `MONOCHROME2`) | Single plane, little-endian, `sampleStride == 2`, `pixelStride >= 2`, `rowBytes >= width * 2`, optional `offset` | 64-byte header + `2` segments (`MSB`, `LSB`) | Unsigned 16-bit round-trip tested; signed two's-complement extrema (`-32768`, `32767`) not separately tested | **R2** — separate unsigned & signed qualification (`-32768`, `-1`, `0`, `32767`, `65535`) + canonical unused-bit handling + `DCMTK`/`GDCM` |
| **DICOM 8-bit & 16-bit `PALETTE COLOR`** | `8`, `16` | `8`, `16` | `.unsignedInteger` | `1` (palette index; LUT stays external in `DICOMKit`/metadata) | Single plane (`1` or `2` bytes/sample) | 64-byte header + `1` (`8`-bit) or `2` (`16`-bit) segments | Treated as 1-sample frame; no dedicated palette index preservation test | **R2** — exact index preservation without LUT expansion |
| **DICOM 8-bit RGB / `YBR_FULL`** | `8` | `8` | `.unsignedInteger` | `3` (`.red`, `.green`, `.blue` or explicit `YBR_FULL` roles; never inferred from count alone) | Both interleaved (`PlanarConfiguration = 0`, 1 plane, `pixelStride >= 3`) and planar (`PlanarConfiguration = 1`, 3 planes) | 64-byte header + `3` segments (`R`, `G`, `B` or `Y`, `Cb`, `Cr`) | `RGB` 8-bit planar `0` and `1` tested (`testRoundTripRGBInterleaved`, `testRoundTripRGBPlanar`) | **R2** — direct strided scatter/gather for both interleaved and planar RAM layouts + `DCMTK`/`GDCM` |
| **DICOM 16-bit RGB / `YBR_FULL`** | `16` | `1...16` (`12`, `16`) | `.unsignedInteger` | `3` (`.red`, `.green`, `.blue` or `YBR_FULL`) | Interleaved (`1` plane, `pixelStride >= 6`) and planar (`3` planes, `sampleStride == 2`) | 64-byte header + `6` segments (`C0_MSB`, `C0_LSB`, `C1_MSB`, `C1_LSB`, `C2_MSB`, `C2_LSB`) | Accepted by `canEncode` (`3 * 2 = 6 <= 15`) and `interleaveSegments`, but **not covered by predecessor tests** | **R2** — explicit 6-segment qualification and `DCMTK`/`GDCM` verification |

---

## 2. Unused bits, metadata and unsupported-profile rules

1. **Canonical `Image` samples vs raw allocated-cell preservation**:
   - Under `MEMORY_CONTRACT.md` (`MEM-01`/`MEM-02`), canonical `Image` samples store meaningful bits low-aligned with zeroed high bits for `.unsignedInteger` and valid two's-complement sign extension across high bits for `.signedInteger`.
   - Under DICOM PS3.5 Section 8.1.1, receivers cannot assume unused high bits in an incoming DICOM RLE frame are already cleared or sign-extended.
   - `SwiftRLE` (`R2`) will distinguish:
     - **Canonical sample-preserving `Image` decode**: masks/sign-extends unused bits (`storageBits > meaningfulBits`, e.g. `12-in-16`) while scattering into the final `ImageDestination` and records the normalization in `OperationReport` without allocating a second full image.
     - **Raw allocated-cell byte preservation**: preserves all `storageBits` verbatim when explicitly requested for raw cell inspection/extraction, and never labels unnormalized cells as a canonical `12`-bit `Image`.
2. **Prohibited display/value transforms**:
   - `SwiftRLE` never performs window/level (`VOI LUT`), modality rescale (`RescaleSlope`/`RescaleIntercept`), `MONOCHROME1` polarity inversion, `YBR_FULL` <-> `RGB` colour conversion, palette LUT expansion or 16-to-8-bit reduction.
3. **Explicitly unsupported / deferred profiles (must reject with `CodecError(.unsupportedFeature, ...)` or `.invalidArgument`)**:
   - **1-bit `BINARY` segmentation**: permitted by DICOM PS3.5 in RLE transfer syntax, but requires bit-packing and frame-boundary rules; deferred as an explicit follow-on profile (`not implemented` in `R0`–`R2`).
   - **32-bit integer or floating-point samples**: rejected in initial milestones until separately specified and qualified.
   - **Chroma-subsampled layouts (`YBR_FULL_422`, `YBR_PARTIAL_420`)**: rejected (`PlaneDescriptor` requires full frame dimensions).
   - **Lossy and near-lossless compression modes**: RLE is strictly lossless; `CompressionMode.lossy` and `.nearLossless` fail at configuration/preflight.
   - **Other RLE dialects (BMP RLE4/RLE8, PCX, TGA, Apple animations)**: outside scope.

---

## 3. Cross-codec transcoding qualification matrix (planned for `R3`+)

`SwiftRLE` core depends on no sibling codec. Real cross-codec transcoding is verified in a separate harness (`R3`) and later in `DICOMKit` (`D3`, deferred):

| Peer codec | Peer repository & current `main` SHA | Planned qualification scope | Status in R0 |
| --- | --- | --- | --- |
| **JPEG-LS (`SwiftJLS`)** | [`raster-labs/SwiftJLS` @ `0791e54a5950bb8082af2218bce3800e03c777b9`](https://github.com/raster-labs/SwiftJLS/commit/0791e54a5950bb8082af2218bce3800e03c777b9) | First mandatory real shared-storage pair (`RLE <-> JPEG-LS` in `R3`): unsigned 16-bit (`16-in-16` and `12-in-16`) single-plane greyscale with one `OwnedImageStorage` allocation and zero intermediate image copies. | **Not executed (R3 gate)** |
| **JPEG 2000 / HTJ2K (`SwiftJ2K`)** | [`raster-labs/SwiftJ2K` @ `be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`](https://github.com/raster-labs/SwiftJ2K/commit/be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748) | Follow-on shared-storage qualification against qualified lossless Part 1 / Part 15 profiles. | **Not executed (R3+ / D3 gate)** |
| **JPEG XL (`SwiftJXL`)** | [`raster-labs/SwiftJXL` @ `3e00d934bef331cdbc7c4be752857dc9eca8f799`](https://github.com/raster-labs/SwiftJXL/commit/3e00d934bef331cdbc7c4be752857dc9eca8f799) | Follow-on shared-storage qualification against qualified modular lossless profiles. | **Not executed (R3+ / D3 gate)** |
| **Lossless JPEG (`SwiftJLI`)** | [`raster-labs/SwiftJLI` @ `d25d4567c7932a0b3fd181901d16ce35a9eded29`](https://github.com/raster-labs/SwiftJLI/commit/d25d4567c7932a0b3fd181901d16ce35a9eded29) | Follow-on shared-storage qualification against supported native lossless SOF3 profiles. | **Not executed (R3+ / D3 gate)** |

---

## 4. Platform and environment matrix (`PLATFORMS.md` `0.7.0`)

| Target environment | Minimum OS / architecture | Product scope | R1 status |
| --- | --- | --- | --- |
| **macOS (Apple Silicon)** | `macOS 26.0`, `arm64` | `SwiftRLE` library + `swiftrle-cli` executable | `SwiftRLE` R1 library, `SwiftRLETests` (`19/19` passed in debug and release) and `Examples/Consumer` executed on native host (`Apple M4`, `macOS 27.0.1`, `Swift 6.4`). `R2` DICOM frame engine and `R3` `swiftrle-cli` remain queued; full OS 26 SDK/platform qualification remains an `R5` gate. |
| **macOS (native Intel)** | `macOS 26.0`, `x86_64` | `SwiftRLE` library + `swiftrle-cli` executable | **Unexecuted (`R5` gate)** |
| **iOS / iPadOS** | `iOS 26.0`, `arm64` (+ Simulator) | `SwiftRLE` library | **Unexecuted (`R5` gate)** |
| **tvOS** | `tvOS 26.0`, `arm64` (+ Simulator) | `SwiftRLE` library | **Unexecuted (`R5` gate)** |
| **visionOS** | `visionOS 26.0`, `arm64` (+ Simulator) | `SwiftRLE` library | **Unexecuted (`R5` gate)** |
| **watchOS** | `watchOS 26.0` (SDK architectures + Simulator) | `SwiftRLE` library (`ResourceLimits.watch`) | **Unexecuted (`R5` gate)** |
| **Linux (ARM64)** | Ubuntu 24.04, `aarch64`, Swift `6.2`+ | `SwiftRLE` library + `swiftrle-cli` executable | **Unexecuted (`R5` gate)** |
| **Linux (x86_64)** | Ubuntu 24.04, `x86_64`, Swift `6.2`+ | `SwiftRLE` library + `swiftrle-cli` executable | **Unexecuted (`R5` gate)** |

Rosetta/emulated runs are supplemental evidence and cannot replace native Intel runtime qualification.
