# SwiftRLE 1.0.0 source release

The first stable standalone SwiftRLE source line contains the Swift package, `SwiftRLE` library and `swiftrle-cli`/manual sources. R0–R5 were independently accepted; R5 merged through [PR #5](https://github.com/raster-labs/SwiftRLE/pull/5) at `942dfb9135321bd8b3339fbbdf2388012d72c4b8` after all five final-head CI jobs in run `40273685051`, artifact audit and merge-tree verification. DEC-12 authorizes the separate 1.0.0 release. See [GitHub releases](https://github.com/raster-labs/SwiftRLE/releases) for the `v1.0.0` source distribution. No prebuilt executable distribution is claimed.

## Swift Package Manager usage

Add these entries inside your `Package` declaration, using your target's name:

```swift
dependencies: [
    .package(url: "https://github.com/raster-labs/SwiftRLE.git", from: "1.0.0")
],
targets: [
    .target(name: "YourTarget", dependencies: [
        .product(name: "SwiftRLE", package: "SwiftRLE")
    ])
]
```

Use `import SwiftRLE` in your Swift source. The library product and module are both `SwiftRLE`; no sibling codec is required. Apple consumers must meet the 26.0 deployment floor.

## Format and API scope

The dependency-free core implements PackBits byte/row streams with incremental decoding and strict DICOM RLE frames with external validated descriptors. Supported image storage is 8/16-bit integer, with declared meaningful precision: unsigned/signed mono and unsigned RGB/YBR_FULL planar/interleaved or palette indices, explicit endian, offsets and padded strides. The `Image` route preserves logical samples and canonical meaningful-bit interpretation; raw allocated-cell decode separately preserves every cell bit. DICOM datasets, transfer syntax negotiation, display/window/rescale operations and clinical policy belong to callers.

Async encode/decode, synchronous inspect and explicitly named synchronous wrappers use retained owning storage. Allocating and caller decode share direct final-output kernels; padding is not encoded. Resource/packet-work/deadline checks remain bounded. Scalar CPU is the shipped backend, with measured automatic address hoisting and an explicit reference selection. SIMD/GPU and automatic frame-parallel backends are not shipped. See [frame semantics](R2_FRAME_PROFILE.md), [API contract](COMMON_API.md) and [R4 engineering evidence](R4_QUALIFICATION.md).

The CLI supports encode/decode/inspect/validate/capabilities, explicit raw/PackBits/DICOM-frame endpoints and restricted attached raw 2D full unsigned UInt16 greyscale NRRD interchange. It ships a matching section-1 manual and isolated PREFIX/DESTDIR installer/update path. Binary stdout may be partial on failure; file publication is transactional. NRRD does not carry a 12-bit/signed/colour preservation promise. The separate development integration package proves only the pinned unsigned 12/16-in-16 greyscale RLE↔JPEG-LS profile; it is not a core dependency or a general codec umbrella. See [CLI/integration profile](R3_INTEGRATION.md).

## Toolchains and qualification limits

Swift tools 6.2 is the resolution minimum, Swift 6.4 the primary toolchain, with Swift 6 language mode. Existing Apple deployment targets remain 26.0; no manifest/platform change accompanies 1.0.0. Qualified release evidence is the owner-approved available native macOS (arm64 and native Intel x86_64, both toolchains) plus iPhone/iPad iOS 26 simulator scope. The accepted five-job CI includes native Mac core/CLI/oracle/integration checks and iOS device/simulator SDK compilation. Earlier Linux/watchOS/tvOS/visionOS evidence is supplemental.

Exact macOS 26.0 runtime and physical iPhone/iPad tests remain **UNEXECUTED**, with their R5 acceptance-gate status **WAIVED_BY_OWNER** under DEC-11. Simulator/SDK evidence is not physical-device or exact minimum-runtime execution. No all-platform, physical-device memory ceiling, security certification or clinical-conformance claim is made. The source release preserves accepted ordinary allocation/copy, independent oracle, sanitizer, sustained deterministic mutation and controlled performance evidence without claiming new campaigns. See [R5 accepted scope and limitations](R5_QUALIFICATION.md) and [security policy](../SECURITY.md).

## Downstream and provenance

DICOMKit's separate review is ongoing. D0–D4 adapter/cutover work remains deferred for a later owner assignment; this release does not inspect/build/edit DICOMKit, adopt SwiftRLE downstream or change its platform floor. No other peer capability is inferred.

SwiftRLE is Apache-2.0 with full inherited DICOMKit MIT notices and pinned source provenance preserved in [NOTICE](../NOTICE), [third-party notices](../THIRD_PARTY_NOTICES.md) and [history](../HISTORY.md). Synthetic fixtures contain no patient data. Version 1.0.0 changes release/help/manual metadata and documentation only; codec algorithms/API, package manifest, contracts, tests/drivers/CI and licences remain identical to accepted R5.
