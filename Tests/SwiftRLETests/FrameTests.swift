// SPDX-License-Identifier: Apache-2.0
import Foundation
import Testing
import Synchronization
@testable import SwiftRLE

@Suite("Strict DICOM frame profile")
struct FrameTests {
    // Independently authored LE header and row-literal packets, never Encoder output.
    static func fixture(_ segments: [[UInt8]]) -> Data {
        var bytes = [UInt8](repeating: 0, count: 64)
        func word(_ n: Int, _ slot: Int) { for j in 0..<4 { bytes[slot*4+j] = UInt8(truncatingIfNeeded: n >> (8*j)) } }
        word(segments.count, 0)
        for (i, segment) in segments.enumerated() { word(bytes.count, i+1); bytes += segment }
        return Data(bytes)
    }
    static func options(_ frame: RLEFrameDescriptor, limits: ResourceLimits = .default, multiplier: Int = 2) throws -> DecodeOptions {
        DecodeOptions(resourceLimits: limits, codecOptions: try CodecOptions(frameDescriptor: frame, maximumPacketOperationsPerOutputByte: multiplier))
    }
    static func cell(_ bytes: UnsafeRawBufferPointer, _ d: ImageDescriptor, _ c: Int, _ x: Int, _ y: Int) throws -> UInt16 {
        // Independent address calculation, does not use the production location helper.
        let plane = try #require(d.planes.first(where: { $0.components.contains(c) }))
        let ci = try #require(plane.components.firstIndex(of: c))
        let p = plane.offset + y * plane.rowBytes + x * plane.pixelStride + ci * plane.sampleStride
        return d.storageBits == 8 ? UInt16(bytes[p]) : try loadUInt16(bytes, at: p, order: d.byteOrder)
    }
    static func source(_ frame: RLEFrameDescriptor, padding: UInt8 = 0xA7, value: (Int,Int,Int) -> UInt16) throws -> Image {
        let d = frame.imageDescriptor
        return try ImageDestination.allocate(descriptor: d).write { bytes in
            bytes.initializeMemory(as: UInt8.self, repeating: padding)
            for plane in d.planes { for y in 0..<d.height { for x in 0..<d.width { for (ci,c) in plane.components.enumerated() {
                let p = plane.offset + y*plane.rowBytes + x*plane.pixelStride + ci*plane.sampleStride
                let v = value(c,x,y)
                if d.storageBits == 8 { bytes[p] = UInt8(truncatingIfNeeded: v) }
                else { try storeUInt16(v, into: bytes, at: p, order: d.byteOrder) }
            } } } }
        }
    }

    @Test func independentLaneFixtureAndEveryTruncation() throws {
        let frame = try RLEFrameDescriptor.greyscale16(width: 3, height: 2, rowBytes: 10, offset: 2)
        let bytes = Self.fixture([[2,0,1,255,2,128,0,18], [2,1,2,255,2,0,255,52]])
        let decoder = try Decoder()
        let decoded = try decoder.decodeSynchronously(bytes, options: Self.options(frame))
        let expected: [UInt16] = [1,258,65535,32768,255,4660]
        for y in 0..<2 { for x in 0..<3 { #expect(try decoded.image.sampleUInt16(x: x,y: y) == expected[y*3+x]) } }
        for n in 0..<bytes.count { #expect(throws: CodecError.self) { _ = try decoder.decodeSynchronously(bytes.prefix(n), options: Self.options(frame)) } }
        let slice = Data([7,8,9]) + bytes
        let sliced = slice.dropFirst(3)
        #expect(sliced.startIndex == 3)
        #expect(try decoder.decodeSynchronously(sliced, options: Self.options(frame)).image.sampleUInt16(x: 2,y: 1) == 4660)
    }

    @Test func malformedHeaderPacketsPaddingAndNOPBudget() throws {
        let frame = try RLEFrameDescriptor(width: 3,height: 1,storageBits: 8,meaningfulBits: 8)
        let opts = try Self.options(frame), decoder = try Decoder()
        let valid = Self.fixture([[2,1,2,3]])
        #expect(try decoder.inspect(valid, options: opts).frameCount == 1)
        for (index,value) in [(0,0),(0,16),(4,63),(4,65),(8,1)] {
            var bad = valid; bad[index] = UInt8(value)
            #expect(throws: CodecError.self) { _ = try decoder.inspect(bad, options: opts) }
        }
        for segment: [UInt8] in [[0,1], [3,1,2,3,4,0], [254], [254,7,1,0], [254,7,0,1], [254,7,128,1], [254,7,0,0]] {
            #expect(throws: CodecError.self) { _ = try decoder.decodeSynchronously(Self.fixture([segment]), options: opts) }
        }
        // Odd packet byte count receives one zero pad, never a missing literal payload.
        let padded = Self.fixture([[0,1,255,2,128,0]])
        #expect(try decoder.decodeSynchronously(padded, options: opts).image.storage.byteCount == 3)
        let flooded = Self.fixture([Array(repeating: 128, count: 72) + [254,7]])
        #expect(throws: CodecError.self) { _ = try decoder.decodeSynchronously(flooded, options: opts) }
        #expect(throws: CodecError.self) { _ = try decoder.decodeSynchronously(Self.fixture([[254,7] + Array(repeating: 128,count: 66)]), options: opts) }
        let crossing = try RLEFrameDescriptor(width: 2,height: 2,storageBits: 8,meaningfulBits: 8)
        #expect(throws: CodecError.self) { _ = try decoder.decodeSynchronously(Self.fixture([[253,7]]), options: Self.options(crossing)) }
        let two = try RLEFrameDescriptor.greyscale16(width: 1,height: 1)
        for offset in [64,63,1000] {
            var bad = Self.fixture([[0,1],[0,2]])
            for n in 0..<4 { bad[8+n] = UInt8(truncatingIfNeeded: offset >> (8*n)) }
            #expect(throws: CodecError.self) { _ = try decoder.inspect(bad, options: Self.options(two)) }
        }
    }

    @Test func canonicalMeaningfulBitsVersusRawCells() throws {
        for signed in [false,true] {
            let frame = try RLEFrameDescriptor(width: 3,height: 1,sampleType: signed ? .signedInteger : .unsignedInteger,
                storageBits: 16,meaningfulBits: 12)
            let fixture = Self.fixture([[2,0xA0,0xA8,0xAF], [2,1,0,255]])
            let result = try Decoder().decodeSynchronously(fixture, options: Self.options(frame))
            let expected: [UInt16] = signed ? [1,0xF800,0xFFFF] : [1,0x800,0xFFF]
            try result.image.storage.withUnsafeBytes { (b: UnsafeRawBufferPointer) throws -> Void in
                for x in 0..<3 { #expect(try Self.cell(b,frame.imageDescriptor,0,x,0) == expected[x]) }
            }
            #expect(result.report.sampleNormalizations.count == 1)
            let raw = try DICOMRLEFrame.decodeAllocatedCells(fixture, descriptor: frame)
            try raw.storage.withUnsafeBytes { (b: UnsafeRawBufferPointer) throws -> Void in
                for (x,v) in [UInt16(0xA001),0xA800,0xAFFF].enumerated() { #expect(try Self.cell(b,frame.imageDescriptor,0,x,0) == v) }
            }
            let noncanonical = try Self.source(frame) { _,x,_ in [0xA001,0xA800,0xAFFF][x] }
            #expect(throws: CodecError.self) { _ = try Encoder().encodeSynchronously(noncanonical) }
        }
    }

    @Test func profileMatrixStridesPaddingEndianAndMutationControls() throws {
        let profiles: [([ComponentRole],ColourInterpretation,SampleType)] = [
            ([.grey],.greyscale,.unsignedInteger), ([.grey],.greyscale,.signedInteger),
            ([.uninterpreted("palette-index")],.unknown,.unsignedInteger),
            ([.red,.green,.blue],.rgb,.unsignedInteger),
            ([.uninterpreted("Y"),.uninterpreted("Cb"),.uninterpreted("Cr")],.unknown,.unsignedInteger)]
        var mutationFailures = [0,0]
        for (roles,colour,type) in profiles { for bits in [8,16] { for precision in bits == 16 ? [12,16] : [8] { for planar in roles.count == 1 ? [0] : [0,1] { for order: ByteOrder in [.littleEndian,.bigEndian] {
            let row = (3 * (planar == 0 ? roles.count : 1) + 4) * (bits/8)
            let frame = try RLEFrameDescriptor(width: 3,height: 2,sampleType: type,storageBits: bits, meaningfulBits: precision,
                byteOrder: order,components: roles,colour: colour,planarConfiguration: planar,rowBytes: row,offset: 2)
            func value(_ c: Int,_ x: Int,_ y: Int) -> UInt16 {
                let maxValue = (1 << precision)-1
                let low = [0,maxValue,1,1 << (precision-1),maxValue-1,0x53][(x+y*3+c)%6] & maxValue
                return UInt16(type == .signedInteger && low & (1 << (precision-1)) != 0 ? low | ((bits == 8 ? 255 : 65535) ^ maxValue) : low)
            }
            let source = try Self.source(frame,value: value)
            let differentPadding = try Self.source(frame,padding: 0x3B,value: value)
            let encoder = try Encoder(), decoder = try Decoder()
            let encoded = try encoder.encodeSynchronously(source)
            #expect(try encoder.encodeSynchronously(differentPadding).data == encoded.data)
            let destinationFrame = try RLEFrameDescriptor(width: 3,height: 2,sampleType: type,storageBits: bits,meaningfulBits: precision,
                byteOrder: order == .littleEndian ? .bigEndian : .littleEndian,components: roles,colour: colour,
                planarConfiguration: roles.count == 1 ? 0 : 1-planar,rowBytes: row+12,offset: 4)
            let recorder = StorageTelemetry.Recorder()
            let result = try StorageTelemetry.$recorder.withValue(recorder) {
                let destination = try ImageDestination.allocate(descriptor: destinationFrame.imageDescriptor)
                let id = destination.storage.allocationID
                let result = try decoder.decodeSynchronously(encoded.data,into: destination, options: Self.options(frame))
                #expect(result.image.storage.allocationID == id)
                #expect(result.report.pixelAllocationCount == 0)
                return result
            }
            #expect(recorder.counts.pixelAllocations == 1)
            #expect(recorder.counts.pixelBytes == destinationFrame.imageDescriptor.requiredByteCount)
            #expect(recorder.counts.workspaceAllocations == 0 && recorder.counts.copyBytes == 0)
            try result.image.storage.withUnsafeBytes { (b: UnsafeRawBufferPointer) throws -> Void in
                var touched = Set<Int>()
                for y in 0..<2 { for x in 0..<3 { for c in roles.indices {
                    #expect(try Self.cell(b,destinationFrame.imageDescriptor,c,x,y) == value(c,x,y))
                    let plane = try #require(destinationFrame.imageDescriptor.planes.first(where: { $0.components.contains(c) }))
                    let ci = try #require(plane.components.firstIndex(of: c))
                    let p = plane.offset+y*plane.rowBytes+x*plane.pixelStride+ci*plane.sampleStride
                    for lane in 0..<bits/8 { touched.insert(p+lane) }
                } } }
                for p in 0..<b.count where !touched.contains(p) { #expect(b[p] == 0) }
            }
            if type == .unsignedInteger && precision == bits {
                for (i,mutation) in [SharedPathMutation.ignoreRowStride,.wrongByteOrder].enumerated() {
                    let altered = try SharedPathMutation.$active.withValue(mutation) { try encoder.encodeSynchronously(source).data }
                    if altered != encoded.data { mutationFailures[i] += 1 }
                }
            }
        } } } } }
        #expect(mutationFailures[0] > 0 && mutationFailures[1] > 0)
        print("Frame mutation controls detected differing codestreams: stride=\(mutationFailures[0]), endian=\(mutationFailures[1]); task-local mutations restored.")
    }

    @Test func limitsMetadataFailureAndUnsupportedProfiles() throws {
        let frame = try RLEFrameDescriptor.greyscale16(width: 3,height: 2)
        let source = try Self.source(frame) { _,x,y in UInt16(x+y*3) }
        let bytes = try Encoder().encodeSynchronously(source).data
        let recorder = StorageTelemetry.Recorder()
        try StorageTelemetry.$recorder.withValue(recorder) {
            for limits in [try ResourceLimits(maximumCompressedBytes: bytes.count-1),
                           try ResourceLimits(maximumDecodedBytes: 11),
                           try ResourceLimits(maximumPixels: 5),
                           try ResourceLimits(maximumDimension: 2),
                           try ResourceLimits(maximumMemoryBytes: bytes.count+11)] {
                #expect(throws: CodecError.self) { _ = try Decoder().decodeSynchronously(bytes, options: Self.options(frame,limits: limits)) }
            }
        }
        #expect(recorder.counts.pixelAllocations == 0)
        let exact = try ResourceLimits(maximumCompressedBytes: bytes.count,maximumDecodedBytes: 12,maximumMemoryBytes: bytes.count+12)
        #expect(try Decoder().decodeSynchronously(bytes,options: Self.options(frame,limits: exact)).report.pixelAllocationCount == 1)
        let destination = try ImageDestination.allocate(descriptor: frame.imageDescriptor)
        var malformed = bytes; malformed[64] = 127
        #expect(throws: CodecError.self) { _ = try Decoder().decodeSynchronously(malformed,into: destination,options: Self.options(frame)) }
        #expect(throws: CodecError.self) { _ = try destination.writeUInt16 { _,_ in 0 } }
        #expect(throws: CodecError.self) { _ = try RLEFrameDescriptor(width: Int.max,height: 2) }
        #expect(throws: CodecError.self) { _ = try RLEFrameDescriptor(width: 1,height: 1,storageBits: 32) }
        #expect(throws: CodecError.self) { _ = try RLEFrameDescriptor(width: 1,height: 1,sampleType: .floatingPoint) }
        #expect(throws: CodecError.self) { _ = try RLEFrameDescriptor(width: 1,height: 1,sampleType: .signedInteger,components: [.red,.green,.blue],colour: .rgb) }
        #expect(throws: CodecError.self) { _ = try RLEFrameDescriptor(width: 1,height: 1,components: [.uninterpreted("YBR_FULL_422")],colour: .unknown) }
        let metadata = ImageMetadata(entries: ["PhotometricInterpretation": Data("MONOCHROME1".utf8)],requiredKeys: ["PhotometricInterpretation"])
        let external = try RLEFrameDescriptor(imageDescriptor: frame.imageDescriptor,metadata: metadata)
        let decoded = try Decoder().decodeSynchronously(bytes,options: Self.options(external))
        #expect(decoded.image.metadata == metadata)
        #expect(throws: CodecError.self) { _ = try Encoder().encodeSynchronously(decoded.image) }
        let encoder = try Encoder(configuration: EncoderConfiguration(codecOptions: CodecOptions(frameDescriptor: external)))
        #expect(try encoder.encodeSynchronously(decoded.image).data == bytes)
    }
    @Test func callbacksCannotBypassAdmissionDeadlineOrCancellation() async throws {
        let frame = try RLEFrameDescriptor.greyscale16(width: 3,height: 2)
        let image = try Self.source(frame) { _,x,y in UInt16(x+y*3) }
        let short = try ResourceLimits(deadlineSeconds: 0.001)
        let delay: @Sendable (ProgressUpdate) -> Void = { update in
            if update.phase == .inspecting { Thread.sleep(forTimeInterval: 0.01) }
        }
        #expect(throws: CodecError.self) { _ = try Encoder().encodeSynchronously(image,options: EncodeOptions(resourceLimits: short,progress: delay)) }
        let data = try Encoder().encodeSynchronously(image).data
        let destination = try ImageDestination.allocate(descriptor: frame.imageDescriptor)
        #expect(throws: CodecError.self) { _ = try Decoder().decodeSynchronously(data,into: destination,
            options: DecodeOptions(resourceLimits: short,codecOptions: CodecOptions(frameDescriptor: frame),progress: delay)) }
        // Callback expiry is still preflight: reservation remains reusable.
        _ = try destination.writeUInt16 { _,_ in 0 }
        let task = Task { () throws -> DecodedImage in
            withUnsafeCurrentTask { $0?.cancel() }
            return try Decoder().decodeSynchronously(data,options: Self.options(frame))
        }
        do { _ = try await task.value; Issue.record("Cancelled frame decode published an image") }
        catch is CancellationError { }
    }

    @Test func requiredMetadataAndICCRemainExternalInBothPolicies() throws {
        let frame = try RLEFrameDescriptor.greyscale16(width: 1,height: 1)
        let image = try Self.source(frame) { _,_,_ in 7 }
        let metadata = ImageMetadata(entries: ["required": Data([1])],requiredKeys: ["required"])
        let annotated = try Image(descriptor: image.descriptor,storage: image.storage,metadata: metadata)
        let d = image.descriptor
        let iccDescriptor = try ImageDescriptor(width: 1,height: 1,planes: d.planes,iccProfile: Data([1,2,3]))
        let icc = try Image(descriptor: iccDescriptor,storage: image.storage)
        for policy: MetadataPolicy in [.preserve,.discardAncillary] {
            #expect(throws: CodecError.self) { _ = try Encoder().encodeSynchronously(annotated,options: EncodeOptions(metadataPolicy: policy)) }
            #expect(throws: CodecError.self) { _ = try Encoder().encodeSynchronously(icc,options: EncodeOptions(metadataPolicy: policy)) }
            let external = try RLEFrameDescriptor(imageDescriptor: iccDescriptor)
            let encoder = try Encoder(configuration: EncoderConfiguration(codecOptions: CodecOptions(frameDescriptor: external)))
            let encoded = try encoder.encodeSynchronously(icc,options: EncodeOptions(metadataPolicy: policy))
            #expect(try Decoder().decodeSynchronously(encoded.data,options: Self.options(external)).image.descriptor.iccProfile == Data([1,2,3]))
        }
    }

    @Test func metadataAdmissionHasBoundedDeadlineAndCancellationChecks() throws {
        let entries = Dictionary(uniqueKeysWithValues: (0..<100_000).map { ("field\($0)", Data([1])) })
        let metadata = ImageMetadata(entries: entries,requiredKeys: Set(entries.keys))
        let base = try RLEFrameDescriptor.greyscale16(width: 1,height: 1)
        let rich = try RLEFrameDescriptor(imageDescriptor: base.imageDescriptor,metadata: metadata)
        let decoder = try Decoder(configuration: DecoderConfiguration(codecOptions: CodecOptions(frameDescriptor: rich)))
        let bytes = Self.fixture([[0,1],[0,2]])
        let limits = try ResourceLimits(deadlineSeconds: 0.001)
        let options = DecodeOptions(resourceLimits: limits)
        let destination = try ImageDestination.allocate(descriptor: base.imageDescriptor)
        let recorder = StorageTelemetry.Recorder()
        try StorageTelemetry.$recorder.withValue(recorder) {
            for operation in 0..<4 {
                do {
                    switch operation {
                    case 0: _ = try decoder.inspect(bytes,options: options)
                    case 1: _ = try decoder.decodeSynchronously(bytes,options: options)
                    case 2: _ = try DICOMRLEFrame.decodeAllocatedCells(bytes,descriptor: rich,options: options)
                    default: _ = try decoder.decodeSynchronously(bytes,into: destination,options: options)
                    }
                    Issue.record("Metadata admission published despite expired deadline")
                } catch let error as CodecError { #expect(error.category == .resourceLimitExceeded) }
            }
        }
        #expect(recorder.counts.pixelAllocations == 0)
        _ = try destination.writeUInt16 { _,_ in 5 }
        // Deterministic callback controls prove checks occur during validation,
        // rather than only at the end of a large entry/key pass.
        enum Stop: Error { case reached }
        var checks = 0
        #expect(throws: Stop.self) {
            _ = try metadata.validate(limits: .default) {
                checks += 1
                if checks == 3 { throw Stop.reached }
            }
        }
        #expect(checks == 3)
        checks = 0
        let longKey = ImageMetadata(entries: [String(repeating: "é",count: 100_000): Data([1])])
        #expect(throws: Stop.self) {
            _ = try longKey.validate(limits: .default) {
                checks += 1
                if checks == 5 { throw Stop.reached }
            }
        }
        #expect(checks == 5)
    }

    @Test func cancellationDuringMetadataValidationRemainsCancellationError() async throws {
        let metadata = ImageMetadata(entries: Dictionary(uniqueKeysWithValues: (0..<10_000).map { ("field\($0)",Data([1])) }))
        let task = Task {
            var checks = 0
            return try metadata.validate(limits: .default) {
                checks += 1
                if checks == 3 { withUnsafeCurrentTask { $0?.cancel() } }
                try Task.checkCancellation()
            }
        }
        do { _ = try await task.value; Issue.record("Metadata validation ignored mid-admission cancellation") }
        catch is CancellationError { }
    }

    @Test func sparseComponentMappingAndPacketBudgetBoundaries() throws {
        // Reversed component mapping, gaps between samples/pixels, explicit prefix.
        let plane = try PlaneDescriptor(width: 3,height: 2,components: [2,0,1],offset: 4,
            sampleStride: 4,pixelStride: 12,rowBytes: 42,byteCount: 88)
        let descriptor = try ImageDescriptor(width: 3,height: 2,components: [.red,.green,.blue],colour: .rgb,planes: [plane])
        let frame = try RLEFrameDescriptor(imageDescriptor: descriptor)
        let source = try Self.source(frame) { c,x,y in UInt16(c*1000+x+y*3) }
        let bytes = try Encoder().encodeSynchronously(source).data
        let packed = try RLEFrameDescriptor(width: 3,height: 2,components: [.red,.green,.blue],colour: .rgb)
        let decoded = try Decoder().decodeSynchronously(bytes,options: Self.options(packed))
        try decoded.image.storage.withUnsafeBytes { (b: UnsafeRawBufferPointer) throws -> Void in
            for y in 0..<2 { for x in 0..<3 { for c in 0..<3 { #expect(try Self.cell(b,packed.imageDescriptor,c,x,y) == UInt16(c*1000+x+y*3)) } } }
        }
        let mono = try RLEFrameDescriptor(width: 1,height: 1,storageBits: 8,meaningfulBits: 8)
        // Base 64 + 2*1 = 66: 65 NOPs plus one literal is exactly the packet budget.
        let at = Self.fixture([Array(repeating: 128,count: 65)+[0,7,0]])
        #expect(try Decoder().decodeSynchronously(at,options: Self.options(mono)).image.storage.byteCount == 1)
        let above = Self.fixture([Array(repeating: 128,count: 66)+[0,7]])
        #expect(throws: CodecError.self) { _ = try Decoder().decodeSynchronously(above,options: Self.options(mono)) }
        let trailingAt = Self.fixture([[0,7]+Array(repeating: 128,count: 64)])
        #expect(try Decoder().decodeSynchronously(trailingAt,options: Self.options(mono)).image.storage.byteCount == 1)
    }

    @Test func rawOptionConflictsAndDestinationMetadataPreflightReuse() throws {
        let frame = try RLEFrameDescriptor.greyscale16(width: 1,height: 1)
        let bytes = Self.fixture([[0,1],[0,2]])
        #expect(throws: CodecError.self) { _ = try DICOMRLEFrame.decodeAllocatedCells(bytes,descriptor: frame,
            options: DecodeOptions(codecOptions: .packBits)) }
        #expect(throws: CodecError.self) { _ = try DICOMRLEFrame.decodeAllocatedCells(bytes,descriptor: frame,
            options: Self.options(RLEFrameDescriptor.greyscale16(width: 2,height: 1))) }
        let metadata = ImageMetadata(entries: ["required": Data([1,2,3])],requiredKeys: ["required"])
        let external = try RLEFrameDescriptor(imageDescriptor: frame.imageDescriptor,metadata: metadata)
        for limits in [try ResourceLimits(maximumMetadataBytes: 1),try ResourceLimits(maximumMemoryBytes: 3)] {
            let destination = try ImageDestination.allocate(descriptor: frame.imageDescriptor,limits: limits)
            #expect(throws: CodecError.self) { _ = try Decoder().decodeSynchronously(bytes,into: destination,options: Self.options(external)) }
            _ = try destination.writeUInt16 { _,_ in 7 }
        }
    }

    @Test func realFrameConcurrentReadersLifetimePaddingAndBegunCancellation() async throws {
        let frame = try RLEFrameDescriptor.greyscale16(width: 3,height: 2,meaningfulBits: 12,rowBytes: 10,offset: 2)
        let recorder = StorageTelemetry.Recorder()
        let bytes = try await StorageTelemetry.$recorder.withValue(recorder) {
            // The caller drops the destination immediately; the Image retains the sealed allocation.
            let source = try Self.source(frame) { _,x,y in UInt16(x+y*3) }
            let encoder = try Encoder()
            let expected = try await encoder.encode(source).data
            try await withThrowingTaskGroup(of: Data.self) { group in
                for _ in 0..<8 { group.addTask { try await encoder.encode(source).data } }
                for try await actual in group { #expect(actual == expected) }
            }
            return expected
        }
        #expect(recorder.counts.pixelAllocations == 1 && recorder.counts.pixelReleases == 1)
        let provider = try FrameSeededStorage(byteCount: frame.imageDescriptor.requiredByteCount)
        let destination = try ImageDestination(descriptor: frame.imageDescriptor,storage: provider)
        let result = try await Decoder().decode(bytes,into: destination,options: Self.options(frame))
        try result.image.storage.withUnsafeBytes { b in
            #expect(b[0] == 0xA5 && b[1] == 0xA5 && b[8] == 0xA5 && b[9] == 0xA5 && b[10] == 0xA5 && b[11] == 0xA5)
        }
        let cancelling = try FrameSeededStorage(byteCount: frame.imageDescriptor.requiredByteCount,cancelAfterFill: true)
        let cancelledDestination = try ImageDestination(descriptor: frame.imageDescriptor,storage: cancelling)
        let task = Task { try await Decoder().decode(bytes,into: cancelledDestination,options: Self.options(frame)) }
        do { _ = try await task.value; Issue.record("Begun decode cancellation published an image") }
        catch is CancellationError { }
        #expect(throws: CodecError.self) { _ = try cancelling.reserveWrite() }
        #expect(throws: CodecError.self) { _ = try cancelledDestination.writeUInt16 { _,_ in 0 } }
    }

}

// Provider retains its actual OwnedImageStorage allocation and forwards the lease.
// This tests advanced caller padding and cancellation after the actual decoder fill.
private final class FrameSeededStorage: WritableImageStorage, Sendable {
    let owner: OwnedImageStorage
    let lease: StorageWriteLease
    let taken = Mutex(false)
    let cancelAfterFill: Bool
    var byteCount: Int { owner.byteCount }
    var allocationID: UUID { owner.allocationID }
    init(byteCount: Int, cancelAfterFill: Bool = false) throws {
        owner = try OwnedImageStorage(byteCount: byteCount)
        lease = try owner.reserveWrite()
        self.cancelAfterFill = cancelAfterFill
        try owner.withUnsafeMutableBytes(lease: lease) { bytes in bytes.initializeMemory(as: UInt8.self,repeating: 0xA5) }
    }
    func reserveWrite() throws -> StorageWriteLease {
        let first = taken.withLock { state in if state { return false }; state = true; return true }
        guard first else { throw CodecError(.storageUnavailable,"Provider already reserved.") }
        return lease
    }
    func withUnsafeMutableBytes<R>(lease: StorageWriteLease,_ body: (UnsafeMutableRawBufferPointer) throws -> R) throws -> R {
        try owner.withUnsafeMutableBytes(lease: lease) { bytes in
            let result = try body(bytes)
            if cancelAfterFill { withUnsafeCurrentTask { $0?.cancel() } }
            return result
        }
    }
    func finishAndSeal(lease: StorageWriteLease) throws -> any ReadOnlyImageStorage { try owner.finishAndSeal(lease: lease) }
    func abortAndInvalidate(lease: StorageWriteLease) throws { try owner.abortAndInvalidate(lease: lease) }
}
