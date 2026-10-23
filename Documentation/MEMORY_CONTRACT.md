# Common image memory and ownership contract

Contract **0.7.0**. All requirements below apply independently in each codec.

## Existing memory layouts, no new image format

**MEM-01.** Use ordinary uncompressed integer/floating-point sample storage with explicit descriptors. The Swift owner and descriptor are an API abstraction, not a serialised file format. The initial shared profile is a single greyscale plane of unsigned 16-bit samples. Apple vImage views and compatible Core Video/IOSurface-backed storage are optional adapters; none is a mandatory core dependency or a substitute for the descriptor. Linux uses the same logical contract. Do not introduce an intermediate TIFF/PNG/NRRD encode/decode inside in-process transcoding.

## Image description

| Field | Contract |
| --- | --- |
| `width`, `height` | Positive pixel dimensions; checked against limits before multiplication |
| `sampleType` | Unsigned integer, signed integer or IEEE floating-point; initial shared profile is unsigned integer |
| `storageBits` | Initial profile 16; general API admits only declared supported widths, initially 8/16 integers and optional 32-bit float |
| `meaningfulBits` | Integer precision, from 1 through storageBits; signed precision includes sign bit; not guessed from observed extrema |
| `byteOrder` | Explicit little/big endian; convenience native-endian requests resolve to a concrete value in a stored descriptor |
| `components` | Ordered component roles; greyscale, RGB, alpha or explicit uninterpreted roles; no inferred colour meaning |
| `colour` | Declared colour interpretation plus optional bounded ICC bytes; unknown is explicit |
| `alpha` | Absent, straight or premultiplied; never silently switch |
| `planes` | Per-plane width/height, component mapping, base offset, sample/pixel stride and positive row stride, byte capacity |
| `metadata` | Bounded image-level metadata with preservation policy; excludes DICOM object semantics |

**MEM-02.** Meaningful integer bits are low-bit aligned in each storage word. Unused high bits are zero for unsigned samples and valid sign extension for signed samples. Padding is not sample data. Values outside declared meaningful range are rejected on encoding, not truncated. Full-precision unsigned 16-bit samples include 0 and 65535; 12-bit unsigned samples include 0 and 4095. This semantic convention uses normal integer storage and does not impose a private file representation.

**MEM-03.** Initial required shared layout: one plane, one component, two-byte sample/pixel stride, little-endian 16-bit storage, at least two-byte alignment, positive even `rowBytes >= width * 2`, no subsampling. Packed and padded rows are required. Each codec must accept this layout for advertised unsigned greyscale lossless input. Additional layouts are capabilities, not implicit assumptions. Do not treat every multi-component codec image as interleaved. Planar/subsampled extensions explicitly describe every plane's dimensions and sampling. A multi-plane layout states the byte distance between consecutive plane origins explicitly; it is never inferred from height and `rowBytes`, because the last row's padding may or may not belong to the plane and the two readings shear the image instead of failing. Consecutive planes may not overlap.

**MEM-04.** Calculate the last accessed byte using checked arithmetic: plane offset plus `(planeHeight - 1) * rowBytes` plus the last pixel/component offsets plus sample bytes. Validate against the retained allocation's capacity before touching memory. Check signed-to-unsigned conversions, plane overlap, stride alignment and row payload separately. Reject negative strides in this baseline. Writable planes cannot overlap. Alignment-sensitive loads must either be proven aligned or use a safe unaligned access strategy. If a backend needs stronger alignment than the shared profile, choose compatible scalar processing or fail/report an explicitly permitted copy.

## Owners and access

**MEM-05.** Every `Image` retains a `ReadOnlyImageStorage` owner and immutable descriptor. Storage exposes capacity, an opaque allocation identity based on a standard UUID, and synchronous scoped read access. It does not expose a persistently valid raw pointer to ordinary application code. The allocation identity follows the underlying allocation across adapter wrappers; a fresh allocation has a different identity. Never log raw addresses in production. Read-only storage is shared, not leased: any number of readers may hold concurrent scoped borrows of one sealed allocation. A source must not impose MEM-06's single-writer lifecycle; sources and destinations are deliberately asymmetric.

The common public construction/access vocabulary is fixed as follows. These are required names and meanings, not implementation snippets:

| Member / operation | Contract |
| --- | --- |
| `ImageDescriptor` validated construction | Throws for invalid geometry/layout/precision; descriptor fields use the names above |
| `Image(descriptor:storage:metadata:)` | Validates an immutable descriptor against sealed read-only storage; retains its owner |
| `ImageDestination(descriptor:storage:)` | Adopts an owning writable provider; validates capacity and reserves through its shared lifecycle |
| `ImageDestination.allocate(descriptor:limits:)` | Allocating convenience that creates the same kind of destination used by caller-storage decode |
| `ReadOnlyImageStorage.byteCount` | Capacity of the retained allocation, not just visible pixel payload |
| `ReadOnlyImageStorage.allocationID` | UUID forwarded identically across views/adapters of one allocation generation |
| `ReadOnlyImageStorage.withUnsafeBytes(_:)` | Synchronous throwing scoped read borrow; pointer must not escape |
| `WritableImageStorage.byteCount`, `allocationID` | Same capacity/identity rules; shared lifecycle is owned by the underlying provider |
| `WritableImageStorage` exclusive lease operations | Reserve one writer, scoped mutable access, finish-and-seal, or abort-and-invalidate; prove a lease token cannot authorise two concurrent overlapping writes |
| `Image.descriptor`, `Image.storage`, `Image.metadata` | Immutable public values/read-only owner for explicit adapter integration |

Milestone 1 must fix the concrete lease-token Swift signatures once, prove their Sendable/lifetime behaviour and mirror that refinement in all four copies before codec migration. Do not let four agents invent incompatible lease methods independently. Ordinary callers use owning destinations; advanced provider implementers are responsible for enforcing the documented lease protocol. Raw `withUnsafe...` access remains an unsafe boundary: a closure type alone does not prevent a malicious caller from returning or saving its pointer. Document the no-escape duty and prefer safe operations for ordinary callers.

**MEM-06.** `ImageDestination` retains `WritableImageStorage` and grants one exclusive write operation. Implement the lifecycle `available -> writing -> sealed` on success, or `available -> writing -> invalid` on failure/cancellation. A sealed image is immutable. A second writer is rejected. A destination cannot be published as an `Image` until every output sample is initialised and all worker/GPU writes finish. Validate descriptor compatibility before entering the writing state where possible. An invalid destination has no readable image view. Caller-storage entry points take the owner, never a raw pointer or buffer view, so that an `async` operation can retain the allocation across suspension while borrowing only inside synchronous work units (MEM-08). An entry point whose parameter is a pointer cannot satisfy that and is not a conforming shared-storage API, whatever its internals do.

**MEM-07.** The owner/provider enforces the lifecycle across all wrappers, including those from different modules. A caller adopting externally managed memory must supply an owner that actually retains the allocation and enforces exclusive access; retaining an unrelated token is insufficient. The advanced unsafe adoption API must state the caller's duties, reject unsupported lifecycle integration and remain separate from safe owning constructors. A safe owning constructor must actually exist for every storage type and be the form used in documentation and examples; unsafe adoption is the named exception, so that its use is visible at the call site rather than being the path of least resistance. Never allow stack memory, escaped array-buffer pointers or a temporary `Data.withUnsafeBytes` pointer to become an asynchronous owner.

**MEM-08.** Pointer borrows are synchronous, nonescaping and cannot span `await`. Async operations retain owning storage and borrow only inside synchronous work units. An internal parallel implementation may issue disjoint region leases after proving bounds and non-overlap. Any unavoidable unchecked Sendable bridge must be narrow, documented with its lifetime/exclusivity proof and exercised by race/lifetime tests. Do not mark the entire buffer implementation unchecked simply to silence Swift 6 errors.

After sealing, multiple readers may share storage; none may mutate it. Destruction releases the allocation exactly once after the last lease and in-flight operation ends. Reference-counted ownership is acceptable. Copy-on-write is permitted only when a requested mutation actually creates a new allocation and the copy is reported; it cannot be used to claim an operation met `requireSharedStorage` after a hidden clone.

**MEM-09.** Pool reuse is optional and bounded. It requires the last published reader to release its lease, completed hardware work, state reset and a new generation/identity before another image is written. Stale views never access reused storage. Do not promise secure erasure unless implemented and tested; do prevent uninitialised bytes or previous-frame padding from being exposed in serialised output. Encode must skip padding; public byte-export APIs must initialise or redact it.

## Decoding into and encoding from shared storage

**MEM-10.** Decoder inspection describes a supported output layout and precision; callers may request the initial shared layout. The allocating decode convenience and caller-destination decode use the same final-output path. Destination decode writes final reconstructed samples directly to the provided plane(s). It may use algorithm workspace, but must not decode to a second full final image and copy that image into the destination as a hidden implementation shortcut. Algorithm workspace is permitted, but each codec states its bound per sample or per row for each operation and reports it under MEM-12. `requireSharedStorage` removes the hand-off copy; it does not by itself reduce peak memory, and a codec whose workspace exceeds the final frame says so rather than leaving a caller to infer otherwise.

The encoder reads the supplied compatible `Image` directly, after decode has sealed it. For JPEG-LS, reading samples into bounded predictor/line workspace is acceptable; materialising the full frame as `[[Int]]` merely to enter the old encoder is a hand-off copy and fails the first end-to-end proof in Milestone 3.

**MEM-11.** For a future umbrella, one storage owner sits above the codecs. Local adapter objects implement each module's local storage protocol around that same owner. Descriptor values are mapped explicitly. Shared allocation identity, capacity and lifecycle are forwarded unchanged. The adapter retains the owner for the whole operation; it does not reconstruct the pixels. The first test harness may perform this role without introducing a production umbrella dependency.

## Copy policy and measurement

| Memory use | Permitted under `requireSharedStorage`? |
| --- | --- |
| Compressed input/output storage | Yes; report separately from decoded pixels |
| One final decoded allocation supplied by the caller | Yes |
| Small descriptor/owner wrappers | Yes |
| Bounded line/tile/predictor/entropy workspace needed by the algorithm | Yes, subject to resource limits and accounting |
| Whole-frame coefficient workspace inherently required by the selected algorithm | Only if justified, budgeted and explicitly reported as workspace |
| Extra full decoded frame for repacking, byte swapping or a legacy API hand-off | No |
| Temporary image file or implicit memory-mapped image staging | No |

**MEM-12.** `allowCopy` permits only value-preserving memory conversions needed for a supported layout. Report every conversion with a reason, source/destination layout, bytes moved and allocation count; conversion byte counts include streamed row-by-row copies. The report includes peak owned pixel bytes and algorithm workspace where measurable. Unknown measurements are marked unknown, never zero. A relabelled final image is not algorithm workspace. The default path must not change from shared to copied because acceleration is preferred; use a compatible backend or return a clear incompatibility. A codec whose native sample order differs from the shared layout converts on the shared path rather than relaxing MEM-03; folded into the write or the read, that conversion costs nothing and removes a separate pass.

**MEM-13.** A shared-storage assertion requires all of: matching allocation identities, observed reads/writes in that allocation, allocation/copy instrumentation proving no intermediate full final frame, and sample-exact output. Address equality alone is insufficient. Inspect the code path as well as allocator telemetry. Test incompatible strides/alignment and failure paths, not only packed happy-path data. Allocator telemetry is invalid under a sanitizer, which may quarantine freed blocks and count them as live; take copy-accounting figures from an ordinary build and record which build produced them. On the encode side compare codestreams byte for byte rather than comparing samples: any difference in what the input stage read changes entropy-coding decisions, so sample equality can pass while a layout fault remains.

## Medical-style precision and portability

No windowing, VOI LUT, modality rescale, colour display conversion or automatic normalisation occurs in this contract. Preserve meaningful bit depth when the source explicitly declares it. Do not infer 12 bits just because a 16-bit image's values happen to fit 12 bits. A destination that cannot represent required precision or interpretation must reject or require an explicit, durable external metadata contract.

The first end-to-end proof in Milestone 3 is unsigned. Signed JPEG-LS/JPEG XL mappings need explicit external interpretation where the codestream cannot record signedness; prove both encode and decode mapping without overflow, especially -32768. Those mappings are not part of the first shared-storage claim. CVPixelBuffer format codes, vImage geometry or raw byte arrays alone do not carry the complete descriptor. Do not use Float16 as a substitute for exact UInt16 samples.

## Failure and limits

Validate resource limits before allocation and re-check on frame/layout changes. Join every worker before completing error cleanup. Failed decodes invalidate their destination; failed encodes publish no successful result. No automatic file spill. Admission failure returns `resourceLimitExceeded`; allocation failure returns a defined error where the allocator permits recovery. Resource limits reduce allocation-failure risk but cannot guarantee recovery from process-level OS termination.

## Compressed-domain intermediates

**MEM-14.** Native J2K ↔ HTJ2K coefficient transcoding and JPEG ↔ JPEG XL bitstream reconstruction may operate without creating an uncompressed Image. This is a justified alternative to the Image-based handoff, not an exception to ownership, resource or disk-staging rules. Quantised wavelet/DCT coefficients and reconstruction metadata are bounded private algorithm workspace retained by their owners; they are not a new serialised interchange format.

Borrow or transfer compatible coefficient storage between stages without redundant whole-coefficient duplication solely to enter a legacy adapter. Report necessary allocation, transformation and copying costs; do not claim universal zero allocations or copies for compressed bytes, entropy work or container assembly. Enforce limits on expanded reconstruction metadata and restored output as well as coefficient dimensions. No intermediate file, temporary memory-mapped scratch file or spill-to-disk fallback. This is an application I/O guarantee, not a promise that the operating system never pages memory.

When J2K ↔ HTJ2K uses a qualified sample path, MEM-05..13 apply unchanged: one final uncompressed allocation, sealed before encoding, with no extra final-image handoff copy under `requireSharedStorage`. Coefficient-only paths must not allocate a pixel image merely to satisfy an interface. In both paths retain all owners across async work, keep borrows scoped, join workers on error/cancellation and publish no partial success.

## Milestone 1 concrete lease refinement — 0.2.1

Every module exports its own `StorageWriteLease: Sendable, Hashable` with an immutable UUID identity and a public fresh-token initialiser for advanced provider implementations. Tokens may be copied; only the issuing provider's current state and exact token identity authorise access. A forged, stale or foreign token fails. The local protocols use these signatures:

```swift
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
```

The provider serialises lifecycle transitions and rejects overlapping or reentrant mutable borrows, even when wrappers forward the same lease. Finishing or aborting while a mutable borrow is active must fail rather than race or deadlock. Successful sealing permanently removes mutable access; the returned read owner retains the same allocation and UUID. A writable provider alone is not a readable image. Advanced implementations must initialise the complete published capacity, including any padding, before sealing and must retain the actual allocation throughout all borrows. Unsafe closure pointers must not escape; these APIs do not make arbitrary caller pointer misuse safe.

`ImageDestination` reserves its provider once, retains it, and offers a synchronous `write(_:) throws -> Image` operation for the feasibility experiment. The closure fills synthetic samples; returning successfully seals the initialised allocation. Throwing or cancellation invalidates it. Abandoning an unsealed destination invalidates its reservation. A copyable destination reference cannot grant a second writer. This operation is an explicit memory-construction utility, not a decoder or private compressed format. Real decoders will use the same lifecycle after all bounded work is joined.

An adapter maps descriptors and local lease tokens explicitly while forwarding one underlying provider's authoritative lifecycle, capacity and allocation UUID. Independently declared protocols remain distinct Swift types. No pointer cast, copied pixel array or inferred type identity is permitted to substitute for that mapping.

Preflight rejection before a write begins does not invalidate a caller's existing destination reservation. Once a fill/write operation begins, thrown errors or cancellation invalidate it and prevent image publication. This distinction lets a caller correct an unsupported operation request without exposing partially written samples. The feasibility codec stubs always reject during preflight and never begin a write.

`Image` and `ImageDestination` constructors additionally accept `limits: ResourceLimits = .default`; allocating destinations retain their supplied limits through publication. ICC and image metadata share the metadata ceiling, and metadata plus retained pixel capacity count towards the operation's admission budget. This preserves explicit caller overrides rather than silently restoring default limits when sealing.

## Shared-storage refinements from the Milestone 3 spikes — 0.6.0

Exploratory spikes ran the caller-storage question against all four predecessor codecs, in both directions, before any migration work. Every amendment above comes from something those spikes measured or broke; nothing here is anticipated design.

**The obstacle is the public image type, not the codec.** In each library the samples reach the codec through exactly one stage, and pointing that stage at caller memory is a small, local change: JPEG-LS already ran its lossless hot path over a flat `UInt16` plane behind a `[[Int]]` façade and needed a row stride; JPEG 2000 needed its final-output stage extracted and reads caller samples at one line of its encoder; JPEG XL reads at `unpackUInt16ToInt32` and writes at `assembleImageFrame`; jpegli reads and writes in one de-interleave and one interleave block. What blocks `requireSharedStorage` is the container each library exposes — `Data` per component, a packed `[UInt8]` with no row stride, or, in jpegli's case, an initialiser that rejects any `data.count` other than the packed frame size. A caller holding a padded plane cannot describe an image without first copying it. The `Image`/`ImageDescriptor` work is therefore not packaging around finished codecs; it is the Milestone 3 work.

**Owners, not pointers, and two different lifecycles.** JPEG 2000's encode and decode are `async`, so a pointer parameter cannot satisfy MEM-08; the destination has to be an owner that retains the allocation across suspension. Sources turned out not to be the mirror of destinations: read-only storage needs no exclusive-write lifecycle and admits concurrent readers, which eight simultaneous encodes sharing one source confirmed by producing identical bytes. MEM-05 and MEM-06 previously described only the destination shape.

**Measured cost.** With caller storage, live heap held after one JPEG 2000 decode fell from 16 MB in 6 blocks to 1 KB in 2 at 2048×2048, and for JPEG XL from 2 MB to nothing at 1024×1024. The JPEG 2000 final-output stage ran 9–35% faster writing the caller's plane, because it skips both the allocation and a byte-swap pass; across a whole decode that difference sits below a developer machine's noise. On the encode side the copy a caller must make today costs 5.5 ms and 8 MB at 2048×2048, while the widening loop costs the same either way. Workspace is the honest counterweight: JPEG 2000 carries a spatial-domain `[Double]` plane at eight bytes per sample per component, four times the final frame, and JPEG XL and jpegli carry `Int32` planes at four. Removing the hand-off does not make these operations smaller overall, which is why MEM-10 now requires the bound to be stated.

**What the spikes broke, and what caught it.** Testing a multi-plane path that had never been exercised found plane origins being inferred from `rowBytes` and height; with padded rows the two defensible readings differ by one row's padding per plane and shear the output rather than failing, which is now forbidden by MEM-03. A shared encode that skipped its container wrapper produced a codestream forty bytes short, caught only because the check compared bytes rather than samples. A harness bound an owner to storage that was released on the same line — the precise MEM-07 hazard, reached within an hour of writing the API, which is why a safe owning constructor is now required to exist rather than merely be permitted. An address-sanitizer run reported 100 MB live on a path holding nothing; a probe showed three 8 MB allocate-and-free pairs reporting a 24 MB delta under the sanitizer against 5 KB without it, so the telemetry, not the code, was at fault.

**Standing limits.** These results cover the initial shared layout only: one plane, one component, unsigned 16-bit, little-endian, lossless. Near-lossless, subsampled, multi-component interleaved and colour-transformed paths are unproven. Big-endian hosts are rejected rather than supported. JPEG 2000's restart-interval parallel encode still copies its plane per chunk. Latency figures come from a developer machine and show magnitude, not a PERF-02 release gate, and no result here has been reproduced in continuous integration.
