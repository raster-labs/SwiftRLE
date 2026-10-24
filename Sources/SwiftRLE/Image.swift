// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization

public struct ImageMetadata: Sendable, Equatable {
    public let entries: [String: Data]
    public let requiredKeys: Set<String>
    public static let empty = Self()
    public init(entries: [String: Data] = [:], requiredKeys: Set<String> = []) {
        self.entries = entries; self.requiredKeys = requiredKeys
    }
    @discardableResult
    func validate(limits: ResourceLimits, additionalBytes: Int = 0,
                  check: () throws -> Void = {}) throws -> Int {
        try check()
        guard requiredKeys.count <= entries.count else {
            throw CodecError(.invalidArgument, "Required metadata has no value.")
        }
        for (index, key) in requiredKeys.enumerated() {
            if index % 64 == 0 { try check() }
            guard entries[key] != nil else { throw CodecError(.invalidArgument, "Required metadata has no value.") }
        }
        var count = additionalBytes
        guard count <= limits.maximumMetadataBytes else {
            throw CodecError(.resourceLimitExceeded, "Metadata limit exceeded.")
        }
        for (index, entry) in entries.enumerated() {
            if index % 64 == 0 { try check() }
            let (key, value) = entry
            // UTF-8 lengths can themselves be large; bound work inside a key,
            // rather than relying on a whole-string scan before the next check.
            var keyBytes = 0
            for _ in key.utf8 {
                if keyBytes % 1024 == 0 { try check() }
                keyBytes = try checkedAdd(keyBytes, 1)
                guard keyBytes <= limits.maximumMetadataBytes else {
                    throw CodecError(.resourceLimitExceeded, "Metadata key exceeds its byte limit.")
                }
            }
            count = try checkedAdd(count, checkedAdd(keyBytes, value.count))
            guard count <= limits.maximumMetadataBytes else {
                throw CodecError(.resourceLimitExceeded, "Metadata limit exceeded.")
            }
        }
        try check()
        return count
    }
    func equivalent(to other: ImageMetadata, check: () throws -> Void) throws -> Bool {
        try check()
        guard entries.count == other.entries.count, requiredKeys.count == other.requiredKeys.count else { return false }
        for (index, key) in requiredKeys.enumerated() {
            if index % 64 == 0 { try check() }
            guard other.requiredKeys.contains(key) else { return false }
        }
        for (index, entry) in entries.enumerated() {
            if index % 64 == 0 { try check() }
            guard let value = other.entries[entry.key], value.count == entry.value.count else { return false }
            let equal = try value.withUnsafeBytes { (a: UnsafeRawBufferPointer) in
                try entry.value.withUnsafeBytes { (b: UnsafeRawBufferPointer) in
                    for p in 0..<a.count {
                        if p % 1024 == 0 { try check() }
                        if a[p] != b[p] { return false }
                    }
                    return true
                }
            }
            if !equal { return false }
        }
        try check()
        return true
    }

}

public struct Image: Sendable {
    public let descriptor: ImageDescriptor
    public let storage: any ReadOnlyImageStorage
    public let metadata: ImageMetadata

    /// `storage` must be a sealed owner, not an escaped pointer or mutable view.
    /// External providers are responsible for making that guarantee across adapters.
    public init(descriptor: ImageDescriptor, storage: any ReadOnlyImageStorage,
                metadata: ImageMetadata = .empty, limits: ResourceLimits = .default) throws {
        try self.init(descriptor: descriptor, storage: storage, metadata: metadata, limits: limits, validation: {})
    }

    init(descriptor: ImageDescriptor, storage: any ReadOnlyImageStorage,
         metadata: ImageMetadata, limits: ResourceLimits, validation: () throws -> Void) throws {
        try validation()
        guard storage.byteCount >= descriptor.requiredByteCount else {
            throw CodecError(.incompatibleImageLayout, "Storage is shorter than the descriptor capacity.")
        }
        try descriptor.validate(limits: limits)
        let metadataBytes = try metadata.validate(limits: limits, additionalBytes: descriptor.iccProfile?.count ?? 0, check: validation)
        guard storage.byteCount <= limits.maximumDecodedBytes,
              try checkedAdd(storage.byteCount, metadataBytes) <= limits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Image exceeds the admission budget.")
        }
        try storage.withUnsafeBytes { bytes in
            guard bytes.count >= descriptor.requiredByteCount, bytes.count == storage.byteCount else {
                throw CodecError(.storageUnavailable, "Provider returned inconsistent capacity.")
            }
        }
        try validation()
        self.descriptor = descriptor; self.storage = storage; self.metadata = metadata
    }

    /// A safe sample accessor for the required greyscale profile; never reads padding.
    public func sampleUInt16(x: Int, y: Int) throws -> UInt16 {
        try validateGreyscale16(descriptor)
        guard x >= 0, y >= 0, x < descriptor.width, y < descriptor.height else {
            throw CodecError(.invalidArgument, "Sample coordinates are outside the image.")
        }
        let plane = descriptor.planes[0]
        // Descriptor validation proves these coordinate calculations fit in Int.
        let offset = plane.offset + y * plane.rowBytes + x * plane.pixelStride
        return try storage.withUnsafeBytes { bytes in
            guard bytes.count >= descriptor.requiredByteCount else {
                throw CodecError(.storageUnavailable, "Provider returned insufficient capacity.")
            }
            // The provider retains sealed storage for this synchronous borrow.
            // Descriptor and capacity checks above prove the two-byte extent.
            return try loadUInt16(bytes, at: offset, order: descriptor.byteOrder)
        }
    }
}

/// Reserves the provider on construction; abandoned destinations abort on release.
/// Only one write call is accepted. A thrown fill or cancellation invalidates the
/// destination, and a sealed image independently retains its immutable owner.
public final class ImageDestination: Sendable {
    public let descriptor: ImageDescriptor
    public let storage: any WritableImageStorage
    private let lease: StorageWriteLease
    private let limits: ResourceLimits
    private let started = Mutex(false)

    public init(descriptor: ImageDescriptor, storage: any WritableImageStorage,
                limits: ResourceLimits = .default) throws {
        try descriptor.validate(limits: limits)
        guard storage.byteCount <= limits.maximumDecodedBytes,
              try checkedAdd(storage.byteCount, descriptor.iccProfile?.count ?? 0) <= limits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Destination exceeds the admission budget.")
        }
        guard storage.byteCount >= descriptor.requiredByteCount else {
            throw CodecError(.incompatibleImageLayout, "Destination storage is too short.")
        }
        self.descriptor = descriptor; self.storage = storage; self.limits = limits
        self.lease = try storage.reserveWrite()
    }
    deinit { try? storage.abortAndInvalidate(lease: lease) }

    /// A decoder calls this when its operation fails after admission but
    /// before the final write began, so that a failed decode never leaves a
    /// destination that can still be published (MEMORY_CONTRACT "Failure and
    /// limits"). Preflight rejections do not call it.
    func invalidateAfterFailure() {
        let first = started.withLock { value in
            guard !value else { return false }
            value = true
            return true
        }
        if first { try? storage.abortAndInvalidate(lease: lease) }
    }

    public static func allocate(descriptor: ImageDescriptor, limits: ResourceLimits = .default) throws -> ImageDestination {
        try descriptor.validate(limits: limits)
        guard try checkedAdd(descriptor.requiredByteCount, descriptor.iccProfile?.count ?? 0) <= limits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Destination exceeds the admission budget.")
        }
        let storage = try OwnedImageStorage(byteCount: descriptor.requiredByteCount, limits: limits)
        return try Self(descriptor: descriptor, storage: storage, limits: limits)
    }

    /// Advanced unsafe fill boundary. Initialise every sample before returning.
    /// The pointer must not escape or be used by asynchronous/concurrent work.
    /// Ordinary callers should prefer `writeUInt16`, which validates sample values.
    /// The caller controls cancellation/work bounds inside this synchronous closure.
    public func write(metadata: ImageMetadata = .empty, _ body: (UnsafeMutableRawBufferPointer) throws -> Void) throws -> Image {
        try writeValidated(metadata: metadata, validate: { try Task.checkCancellation() }, admissionCheck: {}, body)
    }

    func writeValidated(metadata: ImageMetadata, validate: () throws -> Void, admissionCheck: () throws -> Void,
                        _ body: (UnsafeMutableRawBufferPointer) throws -> Void) throws -> Image {
        let metadataBytes = try metadata.validate(limits: limits, additionalBytes: descriptor.iccProfile?.count ?? 0, check: admissionCheck)
        try admissionCheck()
        guard try checkedAdd(storage.byteCount, metadataBytes) <= limits.maximumMemoryBytes else {
            throw CodecError(.resourceLimitExceeded, "Destination metadata exceeds its retained admission budget.")
        }
        let accepted = started.withLock { value in
            guard !value else { return false }
            value = true
            return true
        }
        guard accepted else { throw CodecError(.storageUnavailable, "Destination was already used.") }
        do {
            try validate()
            try storage.withUnsafeMutableBytes(lease: lease) { bytes in
                guard bytes.count == storage.byteCount, bytes.count >= descriptor.requiredByteCount else {
                    throw CodecError(.storageUnavailable, "Provider returned inconsistent capacity.")
                }
                try body(bytes)
            }
            try validate()
            let sealed = try storage.finishAndSeal(lease: lease)
            let image = try Image(descriptor: descriptor, storage: sealed, metadata: metadata, limits: limits, validation: validate)
            // External providers may perform bounded finalisation or validation
            // work. Cancellation during either callback must prevent publication.
            try validate()
            return image
        } catch {
            try? storage.abortAndInvalidate(lease: lease)
            throw error
        }
    }

    /// Synthetic sample initialisation; this is not compression or decompression.
    /// A row is the maximum cancellation interval for the provided scalar writer.
    public func writeUInt16(_ sample: (Int, Int) throws -> UInt16) throws -> Image {
        try validateGreyscale16(descriptor)
        let plane = descriptor.planes[0]
        let maximum = UInt32(1) << descriptor.meaningfulBits
        return try write { bytes in
            for y in 0..<descriptor.height {
                try Task.checkCancellation()
                for x in 0..<descriptor.width {
                    let value = try sample(x, y)
                    guard UInt32(value) < maximum else {
                        throw CodecError(.invalidArgument, "Sample exceeds declared meaningful precision.")
                    }
                    let offset = plane.offset + y * plane.rowBytes + x * plane.pixelStride
                    // The exclusive lease retains these two bytes. External
                    // providers need not initialise samples before this write.
                    try storeUInt16(value, into: bytes, at: offset, order: descriptor.byteOrder)
                }
            }
        }
    }
}

// MARK: - Byte-order-explicit 16-bit sample access

// These replace the `RawSpan.load(fromByteOffset:as:_:)` and
// `OutputRawSpan.append(_:as:_:)` byte-order operations. Those standard-library
// entry points are annotated `@available(macOS 27, *)` and equivalents, so using
// them would raise every Apple deployment floor above the 26.0 baseline that
// PLATFORMS.md PLAT-02 fixes. They are a spelling convenience, not a capability:
// the contract requires an explicit byte order (MEM-01), never a particular
// standard-library type to express it.
//
// Assembling each sample byte-wise keeps two properties the span types provided
// implicitly and that the accessors depend on:
//
//   * Alignment independence. MEM-03 permits any plane `offset`, so a sample may
//     begin at an odd address. Byte access has no alignment precondition.
//   * A bounds check before the allocation is touched (MEM-04). A raw buffer
//     subscript is unchecked in release builds, so the guards below are load
//     bearing, not defensive duplication of the descriptor arithmetic.

@inline(__always)
func loadUInt16(_ bytes: UnsafeRawBufferPointer, at offset: Int,
                order: ByteOrder) throws -> UInt16 {
    guard offset >= 0, offset <= bytes.count - MemoryLayout<UInt16>.size else {
        throw CodecError(.storageUnavailable, "Sample extent lies outside the retained allocation.")
    }
    let first = UInt16(bytes[offset]), second = UInt16(bytes[offset + 1])
    return order == .littleEndian ? first | (second << 8) : (first << 8) | second
}

@inline(__always)
func storeUInt16(_ value: UInt16, into bytes: UnsafeMutableRawBufferPointer,
                 at offset: Int, order: ByteOrder) throws {
    guard offset >= 0, offset <= bytes.count - MemoryLayout<UInt16>.size else {
        throw CodecError(.storageUnavailable, "Sample extent lies outside the retained allocation.")
    }
    let low = UInt8(truncatingIfNeeded: value), high = UInt8(truncatingIfNeeded: value >> 8)
    // Assigning through the raw buffer initialises these bytes, so a provider
    // may hand over uninitialised sample storage under the exclusive lease.
    bytes[offset] = order == .littleEndian ? low : high
    bytes[offset + 1] = order == .littleEndian ? high : low
}

private func validateGreyscale16(_ descriptor: ImageDescriptor) throws {
    guard descriptor.sampleType == .unsignedInteger, descriptor.storageBits == 16,
          descriptor.components == [.grey], descriptor.planes.count == 1 else {
        throw CodecError(.unsupportedFeature, "Sample helper requires unsigned 16-bit greyscale.")
    }
}
