// SPDX-License-Identifier: MIT
import Foundation
import Testing
@testable import SwiftRLE

@Suite("SIMD & Multi-Worker Parallel Acceleration Tests")
struct ParallelAccelerationTests {

    @Test("Multi-worker SIMD DICOM RLE matches 1T scalar bit-for-bit across clinical & RGB profiles")
    func multiWorkerBitExactEquivalence() throws {
        let encoder = try Encoder()
        let decoder = try Decoder()
        let limits1T = try ResourceLimits(maximumWorkers: 1)
        let limits10T = try ResourceLimits(maximumWorkers: 10)

        // 1. 16-bit unsigned & signed 12-in-16 odd dimensions (333 x 197 = 65,601 pixels -> multi-strip!)
        for signed in [false, true] {
            for bits in [12, 16] {
                for bigEndian in [false, true] {
                    let frame = try RLEFrameDescriptor(
                        width: 333,
                        height: 197,
                        sampleType: signed ? .signedInteger : .unsignedInteger,
                        storageBits: 16,
                        meaningfulBits: bits,
                        byteOrder: bigEndian ? .bigEndian : .littleEndian,
                        rowBytes: 333 * 2 + 6,
                        offset: 2
                    )
                    let mask = (UInt32(1) << bits) - 1
                    let image = try FrameTests.source(frame) { _, x, y in
                        // Mix flat border runs and textured interior
                        if x < 24 || x > 308 || y < 12 {
                            return 0
                        }
                        var v = UInt32((x * 131 + y * 977) & 0xFFFF) & mask
                        if signed && (v & (UInt32(1) << (bits - 1))) != 0 {
                            v |= 0xFFFF ^ mask
                        }
                        return UInt16(v)
                    }

                    let encScalar = try encoder.encodeSynchronously(
                        image,
                        options: EncodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU))
                    )
                    let encAccel1T = try encoder.encodeSynchronously(
                        image,
                        options: EncodeOptions(resourceLimits: limits1T, executionPolicy: .required(.accelerated))
                    )
                    let encAccel10T = try encoder.encodeSynchronously(
                        image,
                        options: EncodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated))
                    )
                    #expect(encScalar.report.backend == .scalarCPU)
                    #expect(encAccel1T.report.backend == .accelerated)
                    #expect(encAccel10T.report.backend == .accelerated)
                    #expect(encAccel1T.data == encScalar.data)
                    #expect(encAccel10T.data == encScalar.data)

                    let codec = try CodecOptions(frameDescriptor: frame)
                    let decScalar = try decoder.decodeSynchronously(
                        encScalar.data,
                        options: DecodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU), codecOptions: codec)
                    )
                    let decAccel10T = try decoder.decodeSynchronously(
                        encAccel10T.data,
                        options: DecodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated), codecOptions: codec)
                    )
                    #expect(decScalar.report.backend == .scalarCPU)
                    #expect(decAccel10T.report.backend == .accelerated)
                    let bytesScalar = try decScalar.image.storage.withUnsafeBytes { Data($0) }
                    let bytesAccel = try decAccel10T.image.storage.withUnsafeBytes { Data($0) }
                    #expect(bytesAccel == bytesScalar)
                }
            }
        }

        // 2. 8-bit & 16-bit RGB interleaved and planar (259 x 131 = 33,929 pixels)
        for storageBits in [8, 16] {
            for planar in [0, 1] {
                let frame = try RLEFrameDescriptor(
                    width: 259,
                    height: 131,
                    storageBits: storageBits,
                    meaningfulBits: storageBits,
                    components: [.red, .green, .blue],
                    colour: .rgb,
                    planarConfiguration: planar
                )
                let maxMask = storageBits == 8 ? 255 : 65535
                let image = try FrameTests.source(frame) { c, x, y in
                    if (x / 19 + y / 13) % 4 == 0 {
                        return UInt16((c * 73 + 42) & maxMask)
                    }
                    return UInt16((c * 211 + x * 37 + y * 53) & maxMask)
                }
                let encScalar = try encoder.encodeSynchronously(
                    image,
                    options: EncodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU))
                )
                let encAccel = try encoder.encodeSynchronously(
                    image,
                    options: EncodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated))
                )
                #expect(encAccel.data == encScalar.data)

                let codec = try CodecOptions(frameDescriptor: frame)
                let decScalar = try decoder.decodeSynchronously(
                    encScalar.data,
                    options: DecodeOptions(resourceLimits: limits1T, executionPolicy: .required(.scalarCPU), codecOptions: codec)
                )
                let decAccel = try decoder.decodeSynchronously(
                    encAccel.data,
                    options: DecodeOptions(resourceLimits: limits10T, executionPolicy: .required(.accelerated), codecOptions: codec)
                )
                let bytesScalar = try decScalar.image.storage.withUnsafeBytes { Data($0) }
                let bytesAccel = try decAccel.image.storage.withUnsafeBytes { Data($0) }
                #expect(bytesAccel == bytesScalar)
            }
        }
    }

    @Test("SIMD 16-bit gather rejects noncanonical samples identically to scalar")
    func simdNoncanonicalSampleRejection() throws {
        for signed in [false, true] {
            let frame = try RLEFrameDescriptor(
                width: 64,
                height: 4,
                sampleType: signed ? .signedInteger : .unsignedInteger,
                storageBits: 16,
                meaningfulBits: 12
            )
            let badSample: UInt16 = signed ? 0x1800 : 0x1001
            let badImage = try FrameTests.source(frame) { _, x, y in
                (x == 23 && y == 2) ? badSample : 0
            }
            let encoder = try Encoder()
            #expect(throws: CodecError.self) {
                _ = try encoder.encodeSynchronously(badImage, options: EncodeOptions(executionPolicy: .required(.accelerated)))
            }
        }
    }
}
