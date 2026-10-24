// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import SwiftRLE
import SwiftJLS

/// The RLE owner is authoritative. Adapters retain it, map lease identities,
/// and forward borrows without adopting a pointer or copying pixel storage.
public final class SharedOwner: Sendable {
    public let storage: SwiftRLE.OwnedImageStorage
    private let sealed = Mutex<(any SwiftRLE.ReadOnlyImageStorage)?>(nil)
    public struct Counts: Sendable { public var writes = 0; public var reads = 0 }
    private let counts = Mutex(Counts())
    public var observed: Counts { counts.withLock { $0 } }
    public init(byteCount: Int) throws { storage = try SwiftRLE.OwnedImageStorage(byteCount:byteCount) }
    func write<R>(_ lease: SwiftRLE.StorageWriteLease, _ body:(UnsafeMutableRawBufferPointer)throws->R) throws -> R {
        try storage.withUnsafeMutableBytes(lease:lease) { bytes in
            counts.withLock { $0.writes += 1 }; return try body(bytes)
        }
    }
    func seal(_ lease: SwiftRLE.StorageWriteLease) throws { let view = try storage.finishAndSeal(lease:lease); sealed.withLock { $0 = view } }
    func read<R>(_ body:(UnsafeRawBufferPointer)throws->R) throws -> R {
        guard let view = sealed.withLock({$0}) else { throw SwiftRLE.CodecError(.storageUnavailable,"Not sealed") }
        return try view.withUnsafeBytes { bytes in counts.withLock{$0.reads += 1}; return try body(bytes) }
    }
}
public final class RLEView: SwiftRLE.WritableImageStorage, SwiftRLE.ReadOnlyImageStorage, Sendable {
    public let owner: SharedOwner
    public init(_ owner:SharedOwner) { self.owner = owner }
    public var byteCount: Int { owner.storage.byteCount }
    public var allocationID: UUID { owner.storage.allocationID }
    public func reserveWrite() throws -> SwiftRLE.StorageWriteLease { try owner.storage.reserveWrite() }
    public func withUnsafeMutableBytes<R>(lease:SwiftRLE.StorageWriteLease,_ body:(UnsafeMutableRawBufferPointer)throws->R)throws->R { try owner.write(lease,body) }
    public func finishAndSeal(lease:SwiftRLE.StorageWriteLease)throws->any SwiftRLE.ReadOnlyImageStorage { try owner.seal(lease); return self }
    public func abortAndInvalidate(lease:SwiftRLE.StorageWriteLease)throws { try owner.storage.abortAndInvalidate(lease:lease) }
    public func withUnsafeBytes<R>(_ body:(UnsafeRawBufferPointer)throws->R)throws->R { try owner.read(body) }
}
public final class JLSView: SwiftJLS.WritableImageStorage, SwiftJLS.ReadOnlyImageStorage, Sendable {
    public let owner: SharedOwner
    private let leases = Mutex<[SwiftJLS.StorageWriteLease:SwiftRLE.StorageWriteLease]>([:])
    public init(_ owner:SharedOwner) { self.owner = owner }
    public var byteCount: Int { owner.storage.byteCount }
    public var allocationID: UUID { owner.storage.allocationID }
    public func reserveWrite() throws -> SwiftJLS.StorageWriteLease {
        let authoritative = try owner.storage.reserveWrite(), local = SwiftJLS.StorageWriteLease()
        leases.withLock{$0[local] = authoritative}; return local
    }
    private func lease(_ token:SwiftJLS.StorageWriteLease)throws->SwiftRLE.StorageWriteLease {
        guard let result = leases.withLock({$0[token]}) else { throw SwiftJLS.CodecError(.storageUnavailable,"Foreign or stale lease") }; return result
    }
    public func withUnsafeMutableBytes<R>(lease:SwiftJLS.StorageWriteLease,_ body:(UnsafeMutableRawBufferPointer)throws->R)throws->R { try owner.write(self.lease(lease),body) }
    public func finishAndSeal(lease:SwiftJLS.StorageWriteLease)throws->any SwiftJLS.ReadOnlyImageStorage { try owner.seal(self.lease(lease)); leases.withLock{_ = $0.removeValue(forKey:lease)}; return self }
    public func abortAndInvalidate(lease:SwiftJLS.StorageWriteLease)throws { try owner.storage.abortAndInvalidate(lease:self.lease(lease)); leases.withLock{_ = $0.removeValue(forKey:lease)} }
    public func withUnsafeBytes<R>(_ body:(UnsafeRawBufferPointer)throws->R)throws->R { try owner.read(body) }
}

public enum Transcoder {
    public enum Direction: Sendable, Equatable { case rleToJLS, jlsToRLE }
    public enum Codec: Sendable, Equatable { case rle, jpegLS }
    public enum Operation: Sendable, Equatable { case decode, encode }
    public enum Backend: Sendable, Equatable { case scalarCPU, accelerated }
    public enum Fidelity: Sendable, Equatable {
        case exactSamples, boundedError(Int), lossy, originalBitstream
    }
    public struct CopyEvent: Sendable, Equatable {
        public let reason: String
        public let bytesMoved: Int
        public let sourceLayout: String
        public let destinationLayout: String
    }
    /// Facts mapped from an actual native codec report, never admission estimates.
    /// JPEG-LS does not expose a normalization field; nil records that absence.
    public struct StageReport: Sendable, Equatable {
        public let codec: Codec
        public let operation: Operation
        public let backend: Backend
        public let fallbackReason: String?
        public let fidelity: Fidelity
        public let copyEvents: [CopyEvent]
        public let pixelAllocationCount: Int?
        public let peakPixelBytes: Int?
        public let peakWorkspaceBytes: Int?
        public let elapsedSeconds: Double?
        public let sampleNormalizations: [String]?
    }
    public struct AttributedCopyEvent: Sendable, Equatable {
        public let codec: Codec
        public let operation: Operation
        public let event: CopyEvent
    }
    /// Native reports remain available alongside consolidated, stage-tagged facts.
    /// The owner is counted once, independently of codec caller-storage counters.
    public struct Report: Sendable {
        public let rle: SwiftRLE.OperationReport
        public let jpegLS: SwiftJLS.OperationReport
        public let stages: [StageReport]
        public let sharedPixelAllocationCount: Int
        public let sharedPixelCapacity: Int
        public let admittedRLEWorkspaceBytes: Int
        public let admittedJPEG_LSWorkspaceBytes: Int
        public var admittedWorkspaceBytes: Int { admittedRLEWorkspaceBytes + admittedJPEG_LSWorkspaceBytes }
        /// Sequential stage peaks are a maximum, not a sum. An unknown native
        /// peak stays unknown; a conservative admission bound is not a measurement.
        public var measuredPeakWorkspaceBytes: Int? {
            guard let a = rle.peakWorkspaceBytes, let b = jpegLS.peakWorkspaceBytes else { return nil }
            return max(a,b)
        }
        /// All qualified operations are exact-sample operations. If a future
        /// stage reports another fidelity, retain it without inventing an
        /// aggregate fidelity or hiding source history.
        public var fidelity: Fidelity? { stages.allSatisfy { $0.fidelity == .exactSamples } ? .exactSamples : nil }
        public var codecPixelAllocationCount: Int? {
            guard let a = rle.pixelAllocationCount, let b = jpegLS.pixelAllocationCount else { return nil }
            return a + b
        }
        public var totalPixelAllocationCount: Int? { codecPixelAllocationCount.map { sharedPixelAllocationCount + $0 } }
        /// Native pixel peaks may already include the supplied owner (RLE does).
        /// With no codec allocations the one owner is the exact pixel capacity;
        /// otherwise overlap is unspecified, so do not add native peaks again.
        public var measuredPeakPixelBytes: Int? {
            guard codecPixelAllocationCount == 0 else { return nil }
            return sharedPixelCapacity
        }
        public var copyEvents: [AttributedCopyEvent] { stages.flatMap { stage in stage.copyEvents.map { AttributedCopyEvent(codec:stage.codec,operation:stage.operation,event:$0) } } }
        public var normalizationStages: [StageReport] { stages.filter { !($0.sampleNormalizations ?? []).isEmpty } }
        public var fallbackStages: [StageReport] { stages.filter { $0.fallbackReason != nil } }

        init(rle: SwiftRLE.OperationReport, jpegLS: SwiftJLS.OperationReport,
                         direction: Direction, capacity: Int, rleBound: Int, jlsBound: Int) {
            self.rle = rle; self.jpegLS = jpegLS
            sharedPixelAllocationCount = 1; sharedPixelCapacity = capacity
            admittedRLEWorkspaceBytes = rleBound; admittedJPEG_LSWorkspaceBytes = jlsBound
            func rleFidelity(_ value: SwiftRLE.Fidelity) -> Fidelity {
                switch value { case .exactSamples: .exactSamples; case .boundedError(let n): .boundedError(n); case .lossy: .lossy; case .originalBitstream: .originalBitstream }
            }
            func jlsFidelity(_ value: SwiftJLS.Fidelity) -> Fidelity {
                switch value { case .exactSamples: .exactSamples; case .boundedError(let n): .boundedError(n); case .lossy: .lossy; case .originalBitstream: .originalBitstream }
            }
            let rleStage = StageReport(codec:.rle,operation:direction == .rleToJLS ? .decode : .encode,
                backend:rle.backend == .scalarCPU ? .scalarCPU : .accelerated,
                fallbackReason:rle.fallbackReason,fidelity:rleFidelity(rle.fidelity),
                copyEvents:rle.copyEvents.map { CopyEvent(reason:$0.reason,bytesMoved:$0.bytesMoved,sourceLayout:$0.sourceLayout,destinationLayout:$0.destinationLayout) },
                pixelAllocationCount:rle.pixelAllocationCount,peakPixelBytes:rle.peakPixelBytes,
                peakWorkspaceBytes:rle.peakWorkspaceBytes,elapsedSeconds:rle.elapsedSeconds,
                sampleNormalizations:rle.sampleNormalizations)
            let jlsStage = StageReport(codec:.jpegLS,operation:direction == .rleToJLS ? .encode : .decode,
                backend:jpegLS.backend == .scalarCPU ? .scalarCPU : .accelerated,
                fallbackReason:jpegLS.fallbackReason,fidelity:jlsFidelity(jpegLS.fidelity),
                copyEvents:jpegLS.copyEvents.map { CopyEvent(reason:$0.reason,bytesMoved:$0.bytesMoved,sourceLayout:$0.sourceLayout,destinationLayout:$0.destinationLayout) },
                pixelAllocationCount:jpegLS.pixelAllocationCount,peakPixelBytes:jpegLS.peakPixelBytes,
                peakWorkspaceBytes:jpegLS.peakWorkspaceBytes,elapsedSeconds:jpegLS.elapsedSeconds,
                sampleNormalizations:nil)
            stages = direction == .rleToJLS ? [rleStage,jlsStage] : [jlsStage,rleStage]
        }
    }
    public struct Result: Sendable {
        public let data: Data
        public let allocationID: UUID
        public let reads: Int
        public let writes: Int
        public let admittedBytes: Int
        public let report: Report
    }
    /// Profile intentionally excludes metadata, signed samples, ICC, colour and
    /// noncanonical bit alignment; JPEG-LS records meaningful precision itself.
    private static func requireQualifiedJPEG_LS(_ input:Data) throws {
        func reject() -> SwiftRLE.CodecError { .init(.unsupportedFeature,"Only lossless single-scan JPEG-LS without ancillary/mapping/restart semantics is qualified") }
        guard input.count >= 4 else { throw reject() }
        try input.withUnsafeBytes { (bytes:UnsafeRawBufferPointer) in
            guard bytes[0] == 255,bytes[1] == 216 else { throw reject() }
            var position = 2, markers = 0
            while position < min(bytes.count,65536) {
                try Task.checkCancellation();markers += 1
                guard markers <= 16,position <= bytes.count-4,bytes[position] == 255 else { throw reject() }
                let marker=bytes[position+1],length=Int(bytes[position+2])*256+Int(bytes[position+3])
                guard length >= 2,length <= bytes.count-position-2 else { throw reject() }
                if marker == 218 {
                    guard length == 8,bytes[position+4] == 1,bytes[position+6] == 0,bytes[position+7] == 0,bytes[position+8] == 0,bytes[position+9] == 0 else { throw reject() }
                    return
                }
                guard marker == 247 || (marker == 248 && length == 13 && bytes[position+4] == 1) else { throw reject() }
                position += length+2
            }
            throw reject()
        }
    }
    public static func run(_ input:Data,direction:Direction,width:Int,height:Int,bits:Int,rowBytes:Int,bigEndian:Bool = false,budget:Int = 8*1024*1024) async throws -> Result {
        guard width > 0,height > 0,[12,16].contains(bits),budget > 0 else { throw SwiftRLE.CodecError(.unsupportedFeature,"Unqualified transcode profile") }
        let frame = try SwiftRLE.RLEFrameDescriptor(width:width,height:height,meaningfulBits:bits,byteOrder:bigEndian ? .bigEndian : .littleEndian,rowBytes:rowBytes)
        let jdesc = try SwiftJLS.ImageDescriptor(width:width,height:height,sampleType:.unsignedInteger,storageBits:16,meaningfulBits:bits,byteOrder:bigEndian ? .bigEndian : .littleEndian,components:[.grey],colour:.greyscale,alpha:.absent,planes:[SwiftJLS.PlaneDescriptor(width:width,height:height,components:[0],offset:0,sampleStride:2,pixelStride:2,rowBytes:rowBytes,byteCount:frame.imageDescriptor.requiredByteCount)])
        // Checked aggregate endpoints + one final capacity + both actual peer
        // workspace bounds. The qualified JPEG-LS input has exactly one scan,
        // no restart directory and no metadata/mapping segments (preflight below).
        func add(_ a:Int,_ b:Int)throws->Int { let (n,o) = a.addingReportingOverflow(b); guard !o else { throw SwiftRLE.CodecError(.resourceLimitExceeded,"Budget overflow") }; return n }
        func mul(_ a:Int,_ b:Int)throws->Int { let(n,o) = a.multipliedReportingOverflow(by:b); guard !o else { throw SwiftRLE.CodecError(.resourceLimitExceeded,"Budget overflow") }; return n }
        let samples = try mul(width,height), output = try add(mul(samples,10),68)
        let context = 65536
        let gradientTable = 2*(2*65535+1)*MemoryLayout<Int>.stride
        let scanDirectory = MemoryLayout<Range<Int>>.stride * 2
        let jlsWorkspace = try add(context + gradientTable + scanDirectory, mul(max(output,input.count),2))
        // RLE direct frame kernels allocate no pixel/row workspace; header is
        // fixed 16 words. Reserve that fixed header separately as workspace.
        let rleWorkspace = 16 * MemoryLayout<UInt32>.stride
        let admitted = try add(add(input.count,output),add(frame.imageDescriptor.requiredByteCount,add(jlsWorkspace,rleWorkspace)))
        guard admitted <= budget else { throw SwiftRLE.CodecError(.resourceLimitExceeded,"Aggregate budget denied") }
        // Each API already counts its active compressed endpoint. Subtract
        // only the externally retained input for encode, or reserved future
        // output for decode; never subtract the active endpoint twice.
        let encodeBudget = budget - input.count
        let decodeBudget = budget - output
        let rlimits = try SwiftRLE.ResourceLimits(maximumCompressedBytes:max(input.count,output),maximumDecodedBytes:frame.imageDescriptor.requiredByteCount,maximumWorkspaceBytes:rleWorkspace,maximumMetadataBytes:1,maximumWorkers:2,maximumMemoryBytes:decodeBudget)
        let jlimits = try SwiftJLS.ResourceLimits(maximumCompressedBytes:max(input.count,output),maximumDecodedBytes:frame.imageDescriptor.requiredByteCount,maximumWorkspaceBytes:jlsWorkspace,maximumMetadataBytes:1,maximumWorkers:2,maximumMemoryBytes:decodeBudget)
        let rEncodeLimits = try SwiftRLE.ResourceLimits(maximumCompressedBytes:max(input.count,output),maximumDecodedBytes:frame.imageDescriptor.requiredByteCount,maximumWorkspaceBytes:rleWorkspace,maximumMetadataBytes:1,maximumWorkers:2,maximumMemoryBytes:encodeBudget)
        let jEncodeLimits = try SwiftJLS.ResourceLimits(maximumCompressedBytes:max(input.count,output),maximumDecodedBytes:frame.imageDescriptor.requiredByteCount,maximumWorkspaceBytes:jlsWorkspace,maximumMetadataBytes:1,maximumWorkers:2,maximumMemoryBytes:encodeBudget)
        switch direction {
        case .rleToJLS:
            _ = try SwiftRLE.Decoder(configuration:.init(codecOptions:SwiftRLE.CodecOptions(frameDescriptor:frame))).inspect(input,options:.init(resourceLimits:rlimits))
        case .jlsToRLE:
            try requireQualifiedJPEG_LS(input)
            let info = try SwiftJLS.Decoder().inspect(input,options:.init(resourceLimits:jlimits))
            guard info.descriptor.width == width,info.descriptor.height == height,info.descriptor.meaningfulBits == bits,info.descriptor.components == [.grey],info.descriptor.sampleType == .unsignedInteger,info.metadata.entries.isEmpty else { throw SwiftRLE.CodecError(.unsupportedFeature,"Source interpretation mismatch") }
        }
        // All preflight and aggregate accounting precede the only pixel owner.
        try Task.checkCancellation()
        let owner = try SharedOwner(byteCount:frame.imageDescriptor.requiredByteCount)
        let rle = RLEView(owner), jls = JLSView(owner)
        let outputData: Data
        let rleReport: SwiftRLE.OperationReport
        let jlsReport: SwiftJLS.OperationReport
        switch direction {
        case .rleToJLS:
            let decoder = try SwiftRLE.Decoder(configuration:.init(codecOptions:SwiftRLE.CodecOptions(frameDescriptor:frame)))
            let decoded = try await decoder.decode(input,into:SwiftRLE.ImageDestination(descriptor:frame.imageDescriptor,storage:rle),options:.init(resourceLimits:rlimits))
            rleReport = decoded.report
            try Task.checkCancellation()
            let encoded = try await SwiftJLS.Encoder().encode(SwiftJLS.Image(descriptor:jdesc,storage:jls),options:.init(resourceLimits:jEncodeLimits))
            outputData = encoded.data; jlsReport = encoded.report
        case .jlsToRLE:
            let decoder = try SwiftJLS.Decoder()
            let decoded = try await decoder.decode(input,into:SwiftJLS.ImageDestination(descriptor:jdesc,storage:jls),options:.init(resourceLimits:jlimits))
            jlsReport = decoded.report
            try Task.checkCancellation()
            let encoded = try await SwiftRLE.Encoder().encode(SwiftRLE.Image(descriptor:frame.imageDescriptor,storage:rle),options:.init(resourceLimits:rEncodeLimits))
            outputData = encoded.data; rleReport = encoded.report
        }
        let counts = owner.observed
        return Result(data:outputData,allocationID:owner.storage.allocationID,reads:counts.reads,writes:counts.writes,admittedBytes:admitted,report:Report(rle:rleReport,jpegLS:jlsReport,direction:direction,capacity:owner.storage.byteCount,rleBound:rleWorkspace,jlsBound:jlsWorkspace))
    }
}
