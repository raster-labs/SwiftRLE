# Milestone R0 — Suite common contract inventory and API surface reconciliation

**Date**: 23 October 2026  
**Milestone**: `R0`  
**Contract Manifest**: [Documentation/COMMON_CONTRACT_SHA256.txt](COMMON_CONTRACT_SHA256.txt)

---

## 1. Pinned common-contract sources across the Swift Image Compression Suite

All four sibling repositories in `https://github.com/raster-labs` were inspected via the GitHub API at both the historical September 2026 handoff pins and their current `main` branch heads as of 23 October 2026:

| Repository | Handoff pin (22 Sept 2026, Contract `0.8.0`) | Review pin (23 Sept 2026, Contract `0.10.0`) | Current `main` HEAD (verified 23 Oct 2026) | Current `main` commit date & subject | Contract manifest parity with `SwiftRLE` |
| --- | --- | --- | --- | --- | --- |
| [`raster-labs/SwiftJ2K`](https://github.com/raster-labs/SwiftJ2K) | [`8578b53f52292c04667ca6fca2944708ec198f3b`](https://github.com/raster-labs/SwiftJ2K/commit/8578b53f52292c04667ca6fca2944708ec198f3b) | [`a88413e5754ac9e85c0bd0fdde26754cc5702c8a`](https://github.com/raster-labs/SwiftJ2K/commit/a88413e5754ac9e85c0bd0fdde26754cc5702c8a) | [`be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`](https://github.com/raster-labs/SwiftJ2K/commit/be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748) | `2026-09-25T10:52:36Z` — `Merge pull request #18 from Raster-Lab/release/12.1.0` | **Exact match** (all 7 SHA-256 hashes identical to `a88413e5`) |
| [`raster-labs/SwiftJLS`](https://github.com/raster-labs/SwiftJLS) | [`6aab2622e3ed0b3ee1ec0c9e3a84564bd27fb2db`](https://github.com/raster-labs/SwiftJLS/commit/6aab2622e3ed0b3ee1ec0c9e3a84564bd27fb2db) | *(matched `0.10.0`)* | [`0791e54a5950bb8082af2218bce3800e03c777b9`](https://github.com/raster-labs/SwiftJLS/commit/0791e54a5950bb8082af2218bce3800e03c777b9) | `2026-10-21T10:20:31Z` — `Merge pull request #16 from raster-labs/codex/milestone-4-qualification` | **Exact match** (all 7 SHA-256 hashes identical) |
| [`raster-labs/SwiftJXL`](https://github.com/raster-labs/SwiftJXL) | [`876e5cb285fd1db347a5907179da091959e1fff5`](https://github.com/raster-labs/SwiftJXL/commit/876e5cb285fd1db347a5907179da091959e1fff5) | *(matched `0.10.0`)* | [`3e00d934bef331cdbc7c4be752857dc9eca8f799`](https://github.com/raster-labs/SwiftJXL/commit/3e00d934bef331cdbc7c4be752857dc9eca8f799) | `2026-10-22T10:22:41Z` — `Reconcile Milestone 4 documentation with accepted CI and remaining gates (#36)` | **Exact match** (all 7 SHA-256 hashes identical) |
| [`raster-labs/SwiftJLI`](https://github.com/raster-labs/SwiftJLI) | [`2dc3e4a613df290f16904d5dc541202a44ca9862`](https://github.com/raster-labs/SwiftJLI/commit/2dc3e4a613df290f16904d5dc541202a44ca9862) | *(matched `0.10.0`)* | [`d25d4567c7932a0b3fd181901d16ce35a9eded29`](https://github.com/raster-labs/SwiftJLI/commit/d25d4567c7932a0b3fd181901d16ce35a9eded29) | `2026-10-21T06:08:39Z` — `Merge pull request #24 from raster-labs/codex/jliswift-oct14-parity` | **Exact match** (all 7 SHA-256 hashes identical) |

### 1.1 Missing historical handoff files

The September 2026 instruction documents (`SwiftRLE_Coding_Agent_Instructions.md` §2 and `DICOMKit_RLE_Migration_Agent_Instructions.md` §2) refer to a handoff `README` and `SOURCE_BASELINE.json`. Neither file was present in the supplied handoff directory; only the two Markdown instruction files and the four-page `SwiftRLE_Separation_Explained.pdf` were supplied. All four handoff commit pins (`8578b53f`, `6aab2622`, `876e5cb2`, `2dc3e4a6`) were verified directly against GitHub instead of inventing missing local files.

---

## 2. All seven common contract documents: individual versions and SHA-256 hashes

The suite intentionally updates only the documents changed by a policy/CLI revision rather than relabelling all seven documents with the policy version number:

| Document | Individual heading version at `0.8.0` handoff | SHA-256 at `0.8.0` handoff (`8578b53f` / `6aab2622` / `876e5cb2` / `2dc3e4a6`) | Individual heading version at current `0.10.0` | SHA-256 in `SwiftRLE` & current suite (`a88413e5` / `be4e7a3a` / `0791e54a` / `3e00d934` / `d25d4567`) | Key change between `0.8.0` and `0.10.0` |
| --- | --- | --- | --- | --- | --- |
| [CLI_CONTRACT.md](CLI_CONTRACT.md) | `0.7.0` | `c3c9e08e115a60ec95f14788f8bd970c452226f918efc7dabb2af7f2624ef19c` | **`0.10.0`** | `8d13c6e32b9c0378d58b547a12333f0930488bedd2f7ceb2157d5fad56eea1db` | **CLI-01 case-collision rule**: executable product names must not differ from library/module names only by case (`swiftrle-cli`, target `SwiftRLECLI`, manual `swiftrle-cli.1`). |
| [COMMON_API.md](COMMON_API.md) | `0.7.0` | `6866eeaefff9b707350d974af4d22c13d45cbe8f8797295c2b2e4595db24b8b0` | **`0.7.0`** | `6866eeaefff9b707350d974af4d22c13d45cbe8f8797295c2b2e4595db24b8b0` | Unchanged (`0.7.0` normative API contract). |
| [MEMORY_CONTRACT.md](MEMORY_CONTRACT.md) | `0.7.0` | `77cfb4d14d523cfcca340c6cf5a994f07776a4cfe4577ad20181ba43cc8b7fe2` | **`0.7.0`** | `77cfb4d14d523cfcca340c6cf5a994f07776a4cfe4577ad20181ba43cc8b7fe2` | Unchanged (`0.7.0` `ReadOnlyImageStorage`, `WritableImageStorage`, `StorageWriteLease` lifecycle). |
| [PERFORMANCE.md](PERFORMANCE.md) | `0.7.0` | `139e83f4c670b514940bcbae2d69560e0b28f866b266019ff8c112c0f388343b` | **`0.7.0`** | `139e83f4c670b514940bcbae2d69560e0b28f866b266019ff8c112c0f388343b` | Unchanged (`0.7.0` benchmark methodology and >5% latency/memory, >1% size gates). |
| [PLATFORMS.md](PLATFORMS.md) | `0.7.0` | `2542feedf31bba35099e64c946b45c4a90a2c753e8ef49c2918853de8939e54e` | **`0.7.0`** | `2542feedf31bba35099e64c946b45c4a90a2c753e8ef49c2918853de8939e54e` | Unchanged (`0.7.0` Apple OS 26.0 minima, Swift 6.2 floor, Ubuntu 24.04 Linux). |
| [SUITE_POLICY.md](SUITE_POLICY.md) | `0.8.0` | `90e155a7dbc204407ab44d6e17c2d2c358434d275f83f5585329d88aba7ee406` | **`0.10.0`** | `e463188165bba3bc9f74da077691019f6659200a6cc75b9220a0cbfd55d4c9cd` | Revision `0.9.0` (D3): successor Apple platform floors remain at `26.0` and consumers raise theirs at cutover; Revision `0.10.0`: CLI-01 `-cli` naming. |
| [TESTING.md](TESTING.md) | `0.7.0` | `3d01911ff78d52e593ffdbd0962d19607878abc51fad5862f8cc10a927fca765` | **`0.7.0`** | `3d01911ff78d52e593ffdbd0962d19607878abc51fad5862f8cc10a927fca765` | Unchanged (`0.7.0` unit, oracle, ownership, sanitizer and 1-hour fuzz requirements). |

---

## 3. Reference implementation and independent-consumer call shapes

Inspected from `raster-labs/SwiftJ2K` @ [`be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748`](https://github.com/raster-labs/SwiftJ2K/tree/be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748/Sources/SwiftJ2K) and `raster-labs/SwiftJLS` @ [`0791e54a5950bb8082af2218bce3800e03c777b9`](https://github.com/raster-labs/SwiftJLS/tree/0791e54a5950bb8082af2218bce3800e03c777b9/Sources/SwiftJLS):

### 3.1 Selected reference implementation signatures

This is an abridged reference surface, not a new normative specification or a complete compilable file. The seven pinned contracts remain authoritative; RLE-specific additions below require R1 consumer and lifecycle tests.

```swift
// Error & options
public struct CodecError: Error, Sendable, Equatable {
    public enum Category: String, Sendable, CaseIterable {
        case invalidArgument, malformedInput, unsupportedFormat, unsupportedFeature
        case incompatibleImageLayout, resourceLimitExceeded, storageUnavailable
        case backendUnavailable, ioFailure, internalFailure
    }
    public let category: Category
    public let message: String
    public init(_ category: Category, _ message: String)
}

public enum CompressionMode: Sendable, Equatable {
    case lossless, nearLossless(maximumAbsoluteError: Int), lossy
}
public enum CopyPolicy: Sendable { case requireSharedStorage, allowCopy }
public enum MetadataPolicy: Sendable { case preserve, discardAncillary }
public enum Backend: Sendable { case scalarCPU, accelerated }
public enum ExecutionPolicy: Sendable { case automatic, scalarCPU, preferred(Backend), required(Backend) }

public struct ResourceLimits: Sendable, Equatable {
    public let maximumCompressedBytes: Int
    public let maximumDecodedBytes: Int
    public let maximumWorkspaceBytes: Int
    public let maximumPixels: Int
    public let maximumDimension: Int
    public let maximumFrames: Int
    public let maximumMetadataBytes: Int
    public let maximumICCBytes: Int
    public let maximumNestingDepth: Int
    public let maximumWorkers: Int
    public let deadlineSeconds: Double
    public let maximumMemoryBytes: Int
    public static let general: Self
    public static let watch: Self
    public static let `default`: Self
}

// Storage & descriptors
public struct StorageWriteLease: Sendable, Equatable, Hashable { public init() }
public protocol ReadOnlyImageStorage: Sendable {
    var byteCount: Int { get }
    var allocationID: UUID { get }
    func withUnsafeBytes<R>(_ body: (UnsafeRawBufferPointer) throws -> R) throws -> R
}
public protocol WritableImageStorage: Sendable {
    var byteCount: Int { get }
    var allocationID: UUID { get }
    func reserveWrite() throws -> StorageWriteLease
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,
        _ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R
    func finishAndSeal(lease: StorageWriteLease) throws -> any ReadOnlyImageStorage
    func abortAndInvalidate(lease: StorageWriteLease) throws
}
public final class OwnedImageStorage: WritableImageStorage, Sendable {
    public init(byteCount: Int, limits: ResourceLimits = .default) throws
}

public struct PlaneDescriptor: Sendable, Equatable { ... }
public struct ImageDescriptor: Sendable, Equatable {
    public static func greyscale16(width: Int, height: Int, meaningfulBits: Int = 16,
                                   rowBytes: Int? = nil, offset: Int = 0,
                                   limits: ResourceLimits = .default) throws -> Self
}
public struct Image: Sendable {
    public let descriptor: ImageDescriptor
    public let storage: any ReadOnlyImageStorage
    public let metadata: ImageMetadata
    public init(descriptor: ImageDescriptor, storage: any ReadOnlyImageStorage,
                metadata: ImageMetadata = .empty, limits: ResourceLimits = .default) throws
    public func sampleUInt16(x: Int, y: Int) throws -> UInt16
}
public final class ImageDestination: Sendable {
    public let descriptor: ImageDescriptor
    public let storage: any WritableImageStorage
    public init(descriptor: ImageDescriptor, storage: any WritableImageStorage,
                limits: ResourceLimits = .default) throws
    public static func allocate(descriptor: ImageDescriptor,
                                limits: ResourceLimits = .default) throws -> ImageDestination
    public func write(_ body: (UnsafeMutableRawBufferPointer) throws -> Void) throws -> Image
    public func writeUInt16(_ sample: (Int, Int) throws -> UInt16) throws -> Image
}

// Codec operations
public struct Encoder: Sendable {
    public let configuration: EncoderConfiguration
    public static let capabilities: CodecCapabilities
    public var capabilities: CodecCapabilities { get }
    public init(configuration: EncoderConfiguration = .default) throws
    @concurrent public func encode(_ image: Image, options: EncodeOptions = .init()) async throws -> EncodedImage
}
public struct Decoder: Sendable {
    public let configuration: DecoderConfiguration
    public static let capabilities: CodecCapabilities
    public var capabilities: CodecCapabilities { get }
    public init(configuration: DecoderConfiguration = .init()) throws
    public func inspect(_ data: Data, options: DecodeOptions = .init()) throws -> ImageInfo
    @concurrent public func decode(_ data: Data, options: DecodeOptions = .init()) async throws -> DecodedImage
    @concurrent public func decode(_ data: Data, into destination: ImageDestination,
                                   options: DecodeOptions = .init()) async throws -> DecodedImage
}
```

### 3.2 Independent consumer call shapes

Both inspected consumers construct a 3×2 unsigned greyscale image with 12 meaningful bits in 16-bit storage and padded 8-byte rows, using `ImageDestination.allocate` and `writeUInt16`.

- [SwiftJ2K consumer](https://github.com/raster-labs/SwiftJ2K/blob/be4e7a3ad352759e7a78a90f6a2e2c3b7aa0f748/Examples/Consumer/Sources/Consumer/main.swift): async `encode`, synchronous `inspect`, allocating async `decode`, then sample comparisons. This example does not call the caller-destination overload.
- [SwiftJLS independent consumer](https://github.com/raster-labs/SwiftJLS/blob/0791e54a5950bb8082af2218bce3800e03c777b9/Examples/IndependentConsumer/Sources/Consumer/main.swift): async `encode`, caller-destination async `decode(_:into:)`, destination allocation identity and zero-copy/pixel-allocation report assertions, then sample comparisons. This example does not call `inspect` or allocating `decode`.

These are source-inspected call shapes, not new executions of those consumers during R0. SwiftRLE image operations need an explicit external `RLEFrameDescriptor`, because the compressed DICOM RLE frame header does not contain geometry or sample interpretation.

---

## 4. Reconciling RLE-specific extensions with the common contract (`API-03`, `API-13`)

| Extension area | Requirement from `SwiftRLE` instructions | Reconciliation with `COMMON_API.md` (`0.7.0`) and `SwiftJ2K`/`SwiftJLS` |
| --- | --- | --- |
| **1. Profile selection (`RLEProfile`)** | Explicit `.dicomRLEFrame` vs `.packBits`; never guess dialect from raw bytes or `.rle` extension. | Carried on `CodecOptions.profile` (defaulting to `.dicomRLEFrame` for the `Image`-level `Encoder`/`Decoder`, and `.packBits` for `PackBitsEncoder`/`PackBitsDecoder`). |
| **2. External `RLEFrameDescriptor` container** | `SwiftRLE` instructions §5.2 specify `DecodeOptions.codecOptions.frameDescriptor` used by `inspect` and both `decode` methods; `SwiftJ2K`/`SwiftJLS` place `codecOptions` on `DecoderConfiguration` only. | R1 proposal: retain nonoptional `DecoderConfiguration.codecOptions` and add optional `DecodeOptions.codecOptions: CodecOptions? = nil`. Resolve the frame descriptor as `options.codecOptions?.frameDescriptor ?? configuration.codecOptions.frameDescriptor`; absence in both is an invalid argument. Apply identical resolution to inspect and both decode variants. The optional per-call container distinguishes omission from an explicit override. R1 must specify profile override/conflict rules and compile/test both configuration-based and per-call consumers before claiming compatibility. |
| **3. Raw PackBits byte APIs (`PackBitsEncoder`, `PackBitsDecoder`)** | Separate byte-level APIs requiring `expectedByteCount: Int` (and optional `rowBytes: Int`, `rowCount: Int`) returning `Data` + `OperationReport` without invented image dimensions. | Expose `PackBitsEncoder` (`encode(_:rowBytes:rowCount:options:)`) -> `EncodedBytes(data: Data, report: OperationReport)` and `PackBitsDecoder` (`decode(_:expectedByteCount:rowBytes:rowCount:options:)`) -> `DecodedBytes(data: Data, consumedByteCount: Int, report: OperationReport)`, plus incremental decoding across chunk boundaries. |
| **4. Synchronous wrappers (`API-03`)** | Synchronous `DICOMCore.RLECodec` callers cannot block a Swift concurrency task with a semaphore. | Provide explicit `Encoder.encodeSynchronously(_:options:) throws -> EncodedImage`, `Decoder.decodeSynchronously(_:options:) throws -> DecodedImage` and `Decoder.decodeSynchronously(_:into:options:) throws -> DecodedImage` calling the same scalar kernels directly. |
