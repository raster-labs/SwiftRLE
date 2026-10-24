# SwiftRLE

Standalone PackBits and DICOM RLE frame compression for the **Swift Image Compression Suite**. The library and `swiftrle-cli` have zero external package dependencies.

**R0–R4 are independently accepted and merged. R5 qualification is in progress.** R4 is merged through [PR #4](https://github.com/raster-labs/SwiftRLE/pull/4) at `d43bc2aaec0c511c6e583dea42dcb57298d8a000`; its exact accepted head passed all seven required CI jobs. Final platform/device gates remain open. There is no stable release or tag. See [qualification and remaining gates](Documentation/R5_QUALIFICATION.md).

## Package and platforms

- Repository/package/module/library: [`raster-labs/SwiftRLE`](https://github.com/raster-labs/SwiftRLE), `SwiftRLE`.
- Executable: `swiftrle-cli`; target `SwiftRLECLI`; manual `ManPages/swiftrle-cli.1`.
- Swift tools 6.2 minimum, Swift 6.4 primary; Swift 6 language mode. Apple deployment minima are exactly macOS/iOS/iPadOS/tvOS/visionOS/watchOS 26.0. Linux reference is Ubuntu 24.04, native x86_64 and AArch64.
- Deployment declarations, SDK builds, simulator execution and physical-device qualification are distinct. See the [platform evidence matrix](Documentation/R5_QUALIFICATION.md).

## Supported formats and semantics

PackBits byte APIs support explicit decoded size, optional consistent row geometry and incremental chunks. DICOM RLE frame APIs require an external validated `RLEFrameDescriptor`: the 64-byte header stores segment offsets, not geometry, precision, colour or signedness. Supported integer storage is 8/16 bits with 1…allocated meaningful bits; signed/unsigned mono, unsigned RGB/YBR_FULL planar/interleaved and palette index profiles are explicit. Both byte orders, offsets and padded rows are supported. Float, alpha, subsampling and DICOM dataset parsing are unsupported.

The ordinary `Image` route preserves logical samples and required external interpretation; unused high bits are masked or sign extended on decode and noncanonical input samples are rejected on encode. `DICOMRLEFrame.decodeAllocatedCells` instead preserves all allocated cell bits without claiming a canonical `Image`. No modality rescale, windowing, MONOCHROME1 inversion, LUT expansion or display conversion occurs. See [frame semantics and memory bounds](Documentation/R2_FRAME_PROFILE.md).

Allocating and caller-storage decode share the direct final-output kernel. The encoder reads retained sealed owners directly, skips padding and allocates no intermediate full decoded planes. Resource limits separately admit compressed bytes, final storage (including strides), bounded work and aggregate codec buffers; these are not whole-process RSS guarantees. Scalar CPU is the shipped backend. Automatic execution hoists validated addressing where measured; explicit scalar remains selectable. Preferred unavailable acceleration reports fallback; required unavailable acceleration fails. SIMD, GPU and automatic frame parallelism are unshipped experiments. See [R4 methodology and evidence](Documentation/R4_QUALIFICATION.md).

## CLI and installation

The CLI implements `encode`, `decode`, `inspect`, `validate` and `capabilities`. Formats are explicit: `raw`, `packbits`, `dicom-rle-frame`, and attached raw 2D UInt16 NRRD where applicable. NRRD interchange is full unsigned 16-bit greyscale with explicit endian; it cannot represent a 12-bit or signed/colour preservation promise. Pipes serialize bytes and do not share memory. Binary stdout may be partial on failure; file output uses atomic final-output publication. See [CLI profile/examples](Documentation/R3_INTEGRATION.md) and command help.

Build `swift build -c release -j 2 --product swiftrle-cli`, then install the matching binary/manual together with `PREFIX=/absolute/prefix Scripts/install-cli.sh .build/release/swiftrle-cli`. `DESTDIR` stages both; re-running updates both. Use `man -M /absolute/prefix/share/man swiftrle-cli` for discovery. [R5 qualification](Documentation/R5_QUALIFICATION.md) records clean URL/revision consumption and isolated install/update checks.

## Provenance and scope

SwiftRLE is Apache-2.0 licensed ([LICENSE](LICENSE)); its extracted DICOMKit kernels/tests retain full inherited MIT notices and source pins in [NOTICE](NOTICE), [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md) and [HISTORY.md](HISTORY.md). DICOMKit remains MIT. Synthetic runtime fixtures use deterministic coordinate expressions and independently authored packet vectors, dedicated to CC0; no patient data is used.

The separate pinned SwiftJLS integration package qualifies only the documented unsigned 12/16-in-16 lossless greyscale pair. Other peer pairs remain unqualified. DICOMKit production adapter/cutover D0–D4 is a separate deferred assignment. See [capabilities](Documentation/CAPABILITY_MATRIX.md), [implementation status](IMPLEMENTATION.md), [security](SECURITY.md), [decisions](Documentation/DECISION_RECORD.md), [agent workflow](AGENTS.md) and the seven pinned contracts in [COMMON_CONTRACT_SHA256.txt](Documentation/COMMON_CONTRACT_SHA256.txt).
