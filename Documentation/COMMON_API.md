# Common API contract

Contract **0.7.0**. Normative implementation specification. Consult MILESTONE1.md for the implemented feasibility surface; codec operations remain deferred.

## Public naming and module boundary

**API-01.** The principal package product and module are named exactly `SwiftJ2K`, `SwiftJLS`, `SwiftJXL` or `SwiftJLI`. Each exports the common names below. Applications importing multiple codecs use module-qualified names, for example `SwiftJ2K.Encoder` and `SwiftJLS.Encoder`. Internal targets may preserve useful algorithm boundaries. Retain old type-name aliases only where cheap and unambiguous; old repositories provide the supported compatibility route for older APIs/platforms.

| Type | Meaning |
| --- | --- |
| `Encoder`, `Decoder` | Immutable, reusable configuration holders; no shared mutable per-operation state |
| `EncoderConfiguration`, `DecoderConfiguration` | Validated, immutable codec configuration |
| `EncodeOptions`, `DecodeOptions` | Per-operation resource limits, execution preferences, progress and copy policy |
| `ImageDescriptor`, `PlaneDescriptor` | Validated sample meaning and memory layout; see memory contract |
| `Image` | Immutable, owning view of sealed sample storage and image metadata |
| `ImageDestination` | Owning, exclusive-write destination with a checked lifecycle |
| `ReadOnlyImageStorage`, `WritableImageStorage` | Local protocols for scoped access to retained storage; no global shared protocol module |
| `ImageInfo` | Bounded inspection result: format, geometry, precision, available frame/metadata information |
| `EncodedImage` | `data: Data`, actual encoding description and `report: OperationReport` |
| `DecodedImage` | `image: Image` and `report: OperationReport` |
| `CodecCapabilities` | Explicit supported modes, sample types, precision ranges, layouts and optional features |
| `CodecError` | Stable error category, safe diagnostic context and optional underlying error |

The tables below specify public call shapes implemented by Milestone 1 and behaviour required of later codec milestones. Preserve their implementation and independent-consumer tests on every supported toolchain. Do not invent alternate spellings in individual repositories.

## Common operations

| Operation | Required call shape | Required result/behaviour |
| --- | --- | --- |
| Configure encoder | `Encoder(configuration:)` | Throw on invalid or unsupported configuration; omission uses explicit lossless defaults |
| Configure decoder | `Decoder(configuration:)` | Throw on invalid configuration; default preserves decoded samples |
| Inspect | `Decoder.inspect(_:options:) throws` | Input `Data`; result `ImageInfo`; no full pixel decode; bounded structural inspection |
| Encode | `Encoder.encode(_:options:) async throws` | Input `Image`; result `EncodedImage` |
| Allocate and decode | `Decoder.decode(_:options:) async throws` | Input `Data`; result `DecodedImage` owning its final allocation |
| Decode into storage | `Decoder.decode(_:into:options:) async throws` | Input `Data` and `ImageDestination`; result `DecodedImage` referencing that exact destination on success |
| Query support | `Encoder.capabilities` / `Decoder.capabilities` | Immutable capability descriptions; distinguish encode and decode coverage |

**API-02.** Supply documented default options for every operation. Configuration belongs on construction; options belong on the operation. Do not have one codec require a positional quality argument or return only a raw array while the others use the common pattern. Encoded bytes use Foundation `Data`; a richer result is consistent in all codecs. Extra statistics may be optional fields of the report. Returned images retain their owner independently of the decoder's lifetime.

**API-03.** Synchronous convenience APIs may be added consistently with explicit `encodeSynchronously` and `decodeSynchronously` names; avoid sync/async overload resolution surprises. They use the same kernels and fidelity/error semantics. The initial common requirement is the async surface above and synchronous bounded inspection. No API may wrap synchronous work in `async` and claim it automatically leaves the caller's actor or becomes cancellable.

## Configuration and fidelity

**API-04.** Common `CompressionMode` alternatives are `lossless`, `nearLossless(maximumAbsoluteError:)` and `lossy`. The bounded-error value is in source integer sample units, validated against the codec's support. Codec-specific `codecOptions` hold quality, distance, point-transform, block coding, progression and other distinct controls. Their names and units must be explicit. There is no suite-wide numeric quality scale falsely claiming identical meaning across codecs.

The default is lossless in the API and CLI. Unsupported lossless requests fail. In SwiftJLI this selects the supported native lossless JPEG path, not a high-quality lossy approximation. JPEG-LS near-lossless uses an explicit nonzero error bound. JPEG 2000 reversible transforms and zero-loss quantisation must agree with the lossless declaration. HTJ2K remains an encoder configuration choice inside SwiftJ2K, with standard-compliant output.

**API-05.** In the Image encode/decode API, lossless means identical logical samples after destination decoding, preserving meaningful precision and interpretation. It does not promise identical compressed bytes or recovery of information previously lost by a lossy source. Colour/alpha meaning must be preserved or rejected; no silent colour conversion, rescaling, bit truncation, normalisation or premultiplication. Lossy transform settings are never activated by an effort/performance preset. JPEG-to-JXL byte-reconstructible recompression is a distinct, specialised operation with its own tests.

**API-06.** Integer signedness unsupported by a destination codestream is not made portable by retaining a RAM flag. A mapping that needs external metadata requires an explicit caller contract and round-trip tests including that metadata. Plain standalone output must reject an unrepresentable signedness/precision/colour requirement. Do not quietly invent private markers or a new image file format. Floating-point support is capability-specific; integer lossless behaviour cannot be inferred from float conversions. Non-finite values require an explicit supported policy, otherwise rejection.

## Options, errors and capabilities

**API-07.** Options use common concepts: `resourceLimits`, `executionPolicy`, `copyPolicy`, `metadataPolicy` and optional `progress`. Execution policies include automatic selection and a scalar CPU reference. Optional acceleration requests may be `preferred` (report fallback) or `required` (fail if unavailable). Result reports identify the backend actually used, conversion/copy events, observed fidelity and operation statistics where available. Lossless sample output must agree across backends; lossy tolerances must be explicitly justified and tested.

`OperationReport` uses consistent fields: `backend`, `fallbackReason`, `fidelity`, `copyEvents`, `pixelAllocationCount`, `peakPixelBytes`, `peakWorkspaceBytes` and optional timing statistics. Unknown measurements are optional/unknown, never fabricated as zero. Each copy event records reason, bytes moved and source/destination layout. `MetadataPolicy.preserve` is the default: preserve required sample/colour semantics or fail. An explicit `discardAncillary` mode may discard nonessential annotations and records what was discarded; it never discards the information needed to interpret samples correctly. Treat unknown required metadata conservatively, not as permission to drop it.

**API-08.** `CopyPolicy.requireSharedStorage` is the default for operations on supplied image storage and for direct transcoding. `allowCopy` explicitly permits required, value-preserving layout conversion and must report it. Ordinary allocating decode may allocate its one final image; that is not a hand-off copy. Internal algorithm workspace is accounted separately. Copy permission does not permit precision loss, a new fidelity mode, disk staging or unreported conversions.

**API-09.** Stable error categories: `invalidArgument`, `malformedInput`, `unsupportedFormat`, `unsupportedFeature`, `incompatibleImageLayout`, `resourceLimitExceeded`, `storageUnavailable`, `backendUnavailable`, `ioFailure` and `internalFailure`. Use Swift `CancellationError` consistently for task cancellation; do not wrap it into a different error category. Preserve category across API/CLI/adapter layers. Context may include safe byte offsets and feature identifiers, never pixel contents or patient metadata. Input-caused errors throw; do not trap or exit the process. Assertions are reserved for proven internal programmer invariants.

**API-10.** Capabilities distinguish format support from currently available acceleration and individual operations. A codec may decode modes it cannot encode. Unsupported geometry, sample format, signedness, alpha, interleaving or multi-frame requests fail predictably before expensive work when discoverable. Inspection is not a security or full-conformance certificate. Revalidate data and destination layout during decode; callers may change input between separate calls.

## Concurrency, progress and cancellation

**API-11.** Public immutable values conform to `Sendable` when their ownership makes it valid. Public mutable raw pointers are not freely Sendable. No default main-actor isolation for codec kernels. Select an explicit Swift 6 execution strategy so expensive work cannot block the caller's UI actor. Use bounded structured task groups; keep task-local scratch per operation; join child work and GPU completion before releasing memory. A dependency or annotation that merely suppresses diagnostics is not evidence of safety.

**API-12.** Check cancellation before allocation, between bounded work units and before successful publication. Default operation deadline is part of resource limits. After cancellation, do not return a successful frame or expose a partially written destination. One in-flight hardware unit may complete before safe release; test and document that bound. Never free storage while hardware or workers still reference it.

Progress uses immutable `ProgressUpdate` values and a `@Sendable` callback. Callbacks execute serially per operation, outside internal locks, on a documented non-UI execution context. Progress is monotonic within an operation, has an explicit phase, does not invent a fraction when total work is unknown, and emits terminal success only after publication. No callbacks after the operation has returned. UI consumers dispatch updates to their own actor. Callback frequency is bounded to avoid performance collapse.

## Extension rule and acceptance

**API-13.** Add specialised features through codec-specific options or clearly named extension operations. Each exception must state why the standard operation cannot represent it and include usage/error tests. The common single-image contract does not pretend that JPIP, volume coding, animation or JPEG reconstruction are interchangeable operations.

Contract tests must compile equivalent client examples against all four modules, differing only in the module qualifier and justified codec options. They must exercise behaviour, not only check that types conform. The optional umbrella maps local types explicitly and implements the same mode, resource, error and ownership semantics. It must never use `unsafeBitCast`, reflection-based layout assumptions or a copied protocol declaration as a claim of shared type identity.

## Native format-pair transcoding extension

**API-14.** SwiftJ2K and SwiftJXL provide a local `Transcoder`, `TranscoderConfiguration`, `TranscodeOptions` and `TranscodeTarget` for the native compressed-format pairs below. Use the same constructor/operation pattern: `Transcoder(configuration:) throws`, `Transcoder.transcode(_:to:options:) async throws -> EncodedImage`, and immutable `Transcoder.capabilities`. Input is Foundation `Data`; output identifies its actual format and carries the common operation report. Milestone 1 implements and tests these names/call shapes with empty capabilities and explicit unsupported-operation errors. Real native transcoding remains a later milestone.

| Library | Local target cases / native pairs | Required preservation |
| --- | --- | --- |
| SwiftJ2K | `jpeg2000`, `htj2k`; Part 1 ↔ Part 15 | Exact decoded samples and required interpretation for qualified complete lossless sources; original compressed bytes may change |
| SwiftJXL | `jpegXL`, `jpeg`; existing lossy JPEG ↔ reconstruction-bearing JXL | JPEG → JXL → JPEG restores every original JPEG byte, using the JXL alone for reconstruction |

Use explicit target selection and validated source detection. `TranscodeOptions` reuses `resourceLimits`, `executionPolicy`, `copyPolicy`, `metadataPolicy` and `progress`; constructors/configuration remain validated and immutable. Capabilities list supported directional source/target pairs, preservation guarantees, profile limits and available processing paths. SwiftJLS/SwiftJLI do not acquire placeholder transcoders or new dependencies from this extension. The later optional umbrella can use the same operation pattern through adapters for cross-library pairs.

Defaults preserve the pair's stated fidelity. For J2K/HTJ2K, a conformant coefficient path is preferred; a qualified lossless sample path may use the common shared Image allocation. For JPEG/JXL, reversible coefficient/reconstruction processing is mandatory: no RGB/pixel fallback, quality-driven re-encode, private archive or original-source lookup on reverse. Lossy JPEG input does not make its reversible recompression a lossy operation, nor does reconstruction recover pixels lost in the original JPEG encoding. Missing reconstruction data and unsupported profiles fail explicitly.

The report must distinguish sample preservation from original-bitstream restoration, and identify coefficient/reconstruction versus sample processing. Include actual backend/fallback reason, required workspace and copy events using the established fields; add any new report fields consistently during API feasibility. Do not claim that JPEG reconstruction used a shared pixel image when none was materialised. Precision limits of the JPEG bridge are separate from the general 16-bit Image API. Ancillary-discard options incompatible with original-byte restoration are rejected. These specialised operations are implemented in later codec milestones; Milestone 1 remains feasibility only.
