// SPDX-License-Identifier: Apache-2.0
import Foundation
import Synchronization
import Testing
@testable import SwiftRLE
@testable import SwiftRLECLI

@Suite("R3/R4 CLI backend policy and deadline boundary regressions")
struct CLIRemediationTests {
    private enum PolicyKind: Equatable {
        case automatic
        case scalarCPU
        case preferredAccelerated
        case other
    }

    private func classify(_ policy: ExecutionPolicy) -> PolicyKind {
        switch policy {
        case .automatic: return .automatic
        case .scalarCPU: return .scalarCPU
        case .preferred(.accelerated): return .preferredAccelerated
        default: return .other
        }
    }

    private func expectCLIExit(_ expectedCode: Int32, _ body: () throws -> Void) {
        do {
            try body()
            Issue.record("Expected CLIError(\(expectedCode)), but operation succeeded")
        } catch let error as CLIError {
            #expect(error.code == expectedCode)
        } catch {
            Issue.record("Expected CLIError(\(expectedCode)), got \(error)")
        }
    }

    @Test func backendArgumentMappingFollowsAPIDefaultAndExplicitPolicies() throws {
        let baseArgs = ["encode", "-i", "in.bin", "--input-format", "raw", "--output-format", "packbits", "-o", "out.pb"]

        let omitted = try Arguments(baseArgs)
        try omitted.validate()
        #expect(classify(try omitted.executionPolicy()) == .automatic)

        let automatic = try Arguments(baseArgs + ["--backend", "automatic"])
        try automatic.validate()
        #expect(classify(try automatic.executionPolicy()) == .automatic)

        for flag in ["scalar", "scalar-cpu"] {
            let scalar = try Arguments(baseArgs + ["--backend", flag])
            try scalar.validate()
            #expect(classify(try scalar.executionPolicy()) == .scalarCPU)
        }

        let preferred = try Arguments(baseArgs + ["--backend", "preferred-accelerated"])
        try preferred.validate()
        #expect(classify(try preferred.executionPolicy()) == .preferredAccelerated)

        let required = try Arguments(baseArgs + ["--backend", "required-accelerated"])
        expectCLIExit(4) { try required.validate() }
        expectCLIExit(4) { _ = try required.executionPolicy() }

        let invalid = try Arguments(baseArgs + ["--backend", "gpu"])
        expectCLIExit(2) { try invalid.validate() }
        expectCLIExit(2) { _ = try invalid.executionPolicy() }
    }

    @Test func runConsumesResolvedExecutionPolicyAcrossPackBitsAndDICOM() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftrle-cli-policy-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let cases: [(flag: String?, expected: PolicyKind)] = [
            (nil, .automatic),
            ("automatic", .automatic),
            ("scalar", .scalarCPU),
            ("scalar-cpu", .scalarCPU),
            ("preferred-accelerated", .preferredAccelerated)
        ]

        // 1. PackBits encode & decode
        let rawInput = dir.appendingPathComponent("raw.bin")
        let rawBytes = Data([10, 10, 10, 21, 32, 43, 43, 99])
        try rawBytes.write(to: rawInput)

        var referencePackBits: Data?
        for (index, item) in cases.enumerated() {
            let pbOut = dir.appendingPathComponent("out-\(index).packbits")
            var encArgs = ["encode", "-i", rawInput.path, "--input-format", "raw", "--output-format", "packbits", "-o", pbOut.path]
            if let flag = item.flag { encArgs += ["--backend", flag] }
            let parsedEnc = try Arguments(encArgs)
            try parsedEnc.validate()

            var observedEnc: [PolicyKind] = []
            try Main.run(
                parsedEnc,
                control: Control(seconds: 30),
                observeEncodeOptions: { observedEnc.append(classify($0.executionPolicy)) }
            )
            #expect(observedEnc == [item.expected])

            let encoded = try Data(contentsOf: pbOut)
            if let ref = referencePackBits { #expect(encoded == ref) } else { referencePackBits = encoded }

            let decOut = dir.appendingPathComponent("dec-\(index).bin")
            var decArgs = [
                "decode", "-i", pbOut.path, "--input-format", "packbits",
                "--decoded-bytes", "\(rawBytes.count)", "--output-format", "raw", "-o", decOut.path
            ]
            if let flag = item.flag { decArgs += ["--backend", flag] }
            let parsedDec = try Arguments(decArgs)
            try parsedDec.validate()

            var observedDec: [PolicyKind] = []
            try Main.run(
                parsedDec,
                control: Control(seconds: 30),
                observeDecodeOptions: { observedDec.append(classify($0.executionPolicy)) }
            )
            #expect(observedDec == [item.expected])
            #expect(try Data(contentsOf: decOut) == rawBytes)
        }

        // 2. Non-singleton DICOM RLE frame (4x3 16-bit greyscale, exercising R4 automatic vs scalar addressing)
        let frameInput = dir.appendingPathComponent("frame.raw")
        var framePixels = Data(capacity: 24)
        for sample: UInt16 in [0, 511, 511, 1024, 2048, 4095, 17, 17, 17, 300, 900, 65535] {
            var le = sample.littleEndian
            withUnsafeBytes(of: &le) { framePixels.append(contentsOf: $0) }
        }
        try framePixels.write(to: frameInput)

        let frameFlags = [
            "--width", "4", "--height", "3", "--storage-bits", "16", "--meaningful-bits", "16",
            "--sample-type", "unsigned", "--components", "1", "--colour", "greyscale",
            "--byte-order", "little", "--planar-configuration", "0"
        ]

        var referenceFrame: Data?
        for (index, item) in cases.enumerated() {
            let rleOut = dir.appendingPathComponent("frame-\(index).rle")
            var encArgs = ["encode", "-i", frameInput.path, "--input-format", "raw", "--output-format", "dicom-rle-frame", "-o", rleOut.path] + frameFlags
            if let flag = item.flag { encArgs += ["--backend", flag] }
            let parsedEnc = try Arguments(encArgs)
            try parsedEnc.validate()

            var observedEnc: [PolicyKind] = []
            try Main.run(
                parsedEnc,
                control: Control(seconds: 30),
                observeEncodeOptions: { observedEnc.append(classify($0.executionPolicy)) }
            )
            #expect(observedEnc == [item.expected])

            let encodedFrame = try Data(contentsOf: rleOut)
            if let ref = referenceFrame { #expect(encodedFrame == ref) } else { referenceFrame = encodedFrame }

            let decOut = dir.appendingPathComponent("frame-dec-\(index).raw")
            var decArgs = ["decode", "-i", rleOut.path, "--input-format", "dicom-rle-frame", "--output-format", "raw", "-o", decOut.path] + frameFlags
            if let flag = item.flag { decArgs += ["--backend", flag] }
            let parsedDec = try Arguments(decArgs)
            try parsedDec.validate()

            var observedDec: [PolicyKind] = []
            try Main.run(
                parsedDec,
                control: Control(seconds: 30),
                observeDecodeOptions: { observedDec.append(classify($0.executionPolicy)) }
            )
            // DICOM decode runs inspect(decodeOptions()) then decodeSynchronously(decodeOptions()).
            #expect(observedDec == [item.expected, item.expected])
            #expect(try Data(contentsOf: decOut) == framePixels)
        }

        // Direct run defence-in-depth for required-accelerated without validate()
        let requiredOut = dir.appendingPathComponent("never-created.packbits")
        let unvalidatedRequired = try Arguments([
            "encode", "-i", rawInput.path, "--input-format", "raw", "--output-format", "packbits",
            "-o", requiredOut.path, "--backend", "required-accelerated"
        ])
        expectCLIExit(4) { try Main.run(unvalidatedRequired, control: Control(seconds: 30)) }
        #expect(!FileManager.default.fileExists(atPath: requiredOut.path))
    }

    @Test func remainingDeadlineUsesSingleClockSampleAndDeterministicBoundaries() throws {
        let t0 = ContinuousClock.now

        // 1. Before deadline: integer and fractional subsecond remaining values, exactly 1 clock sample each.
        for (timeout, elapsedNanos, expectedRemaining) in [
            (10.0, Int64(2_000_000_000), 8.0),
            (1.0, Int64(625_000_000), 0.375),
            (0.05, Int64(49_000_000), 0.001),
            (1.0, Int64(999_999_999), 1e-9)
        ] {
            let reads = Mutex(0)
            let sample = t0.advanced(by: .nanoseconds(elapsedNanos))
            let control = Control(seconds: timeout, started: t0, now: {
                reads.withLock { $0 += 1 }
                return sample
            })
            let remaining = try control.remainingDeadlineSeconds()
            #expect(reads.withLock { $0 } == 1)
            #expect(abs(remaining - expectedRemaining) < 1e-12)

            let limits = try control.resourceLimits(memory: 1_048_576, threads: 2)
            #expect(reads.withLock { $0 } == 2)
            #expect(abs(limits.deadlineSeconds - expectedRemaining) < 1e-12)
        }

        // 2. Exact deadline (0 remaining) and after deadline (< 0 remaining) -> CLIError(5), single clock sample.
        for deltaNanos: Int64 in [0, 1, 2_500_000_000] {
            let reads = Mutex(0)
            let sample = t0.advanced(by: .seconds(1.0)).advanced(by: .nanoseconds(deltaNanos))
            let control = Control(seconds: 1.0, started: t0, now: {
                reads.withLock { $0 += 1 }
                return sample
            })
            expectCLIExit(5) { _ = try control.remainingDeadlineSeconds() }
            #expect(reads.withLock { $0 } == 1)
            expectCLIExit(5) { _ = try control.resourceLimits(memory: 1_048_576, threads: 2) }
            #expect(reads.withLock { $0 } == 2)
            expectCLIExit(5) { try control.check() }
            #expect(reads.withLock { $0 } == 3)
        }
    }

    @Test func cancellationPriority130WinsBeforeAtAndAfterDeadline() async throws {
        let t0 = ContinuousClock.now
        let instants = [
            t0.advanced(by: .milliseconds(100)),
            t0.advanced(by: .seconds(1.0)),
            t0.advanced(by: .seconds(5.0))
        ]

        // 1. Control.cancelled atomic priority over expired/exact/unexpired deadline (0 clock reads needed).
        for sample in instants {
            let reads = Mutex(0)
            let control = Control(seconds: 1.0, started: t0, now: {
                reads.withLock { $0 += 1 }
                return sample
            })
            control.cancelled.store(true, ordering: .relaxed)
            expectCLIExit(130) { _ = try control.remainingDeadlineSeconds() }
            expectCLIExit(130) { _ = try control.resourceLimits(memory: 1_048_576, threads: 2) }
            expectCLIExit(130) { try control.check() }
            #expect(reads.withLock { $0 } == 0)
        }

        // 2. Swift Task cancellation priority over expired/exact/unexpired deadline.
        for sample in instants {
            let control = Control(seconds: 1.0, started: t0, now: { sample })
            let task = Task<Int32, Never> {
                withUnsafeCurrentTask { $0?.cancel() }
                do {
                    _ = try control.resourceLimits(memory: 1_048_576, threads: 2)
                    return 0
                } catch let error as CLIError {
                    return error.code
                } catch {
                    return -1
                }
            }
            #expect(await task.value == 130)
        }
    }

    @Test func runRejectsExpiredDeadlineAsExit5AtBothInitialLimitsAndCurrentLimits() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("swiftrle-cli-deadline-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let inputPath = dir.appendingPathComponent("small.bin")
        try Data([1, 2, 3, 4]).write(to: inputPath)

        let t0 = ContinuousClock.now
        let before = t0.advanced(by: .milliseconds(100))
        let atDeadline = t0.advanced(by: .seconds(1.0))
        let afterDeadline = t0.advanced(by: .milliseconds(1250))

        // StreamIO.readInput for a 4-byte file performs two ready() checks (data read, then EOF read):
        // sample #1 -> ready() before read(4 bytes)
        // sample #2 -> ready() before read(0 EOF)
        // sample #3 -> initial `let limits = try control.resourceLimits(...)` in Main.run
        // sample #4 -> `currentLimits()` inside `encodeOptions()` / `decodeOptions()` in Main.run

        for (index, expiredInstant) in [atDeadline, afterDeadline].enumerated() {
            // Case A: expires on sample #3 (initial limits construction in Main.run)
            let outInitial = dir.appendingPathComponent("initial-\(index).pb")
            let argsInitial = try Arguments([
                "encode", "-i", inputPath.path, "--input-format", "raw",
                "--output-format", "packbits", "-o", outInitial.path
            ])
            try argsInitial.validate()
            let scheduleInitial = Mutex([before, before, expiredInstant])
            let controlInitial = Control(seconds: 1.0, started: t0, now: {
                scheduleInitial.withLock { list in
                    list.isEmpty ? expiredInstant : list.removeFirst()
                }
            })
            expectCLIExit(5) { try Main.run(argsInitial, control: controlInitial) }
            #expect(!FileManager.default.fileExists(atPath: outInitial.path))

            // Case B: initial limits succeeds on sample #3, expires on sample #4 (currentLimits() in encodeOptions)
            let outCurrentEnc = dir.appendingPathComponent("current-enc-\(index).pb")
            let argsCurrentEnc = try Arguments([
                "encode", "-i", inputPath.path, "--input-format", "raw",
                "--output-format", "packbits", "-o", outCurrentEnc.path
            ])
            try argsCurrentEnc.validate()
            let scheduleCurrentEnc = Mutex([before, before, before, expiredInstant])
            let controlCurrentEnc = Control(seconds: 1.0, started: t0, now: {
                scheduleCurrentEnc.withLock { list in
                    list.isEmpty ? expiredInstant : list.removeFirst()
                }
            })
            expectCLIExit(5) { try Main.run(argsCurrentEnc, control: controlCurrentEnc) }
            #expect(!FileManager.default.fileExists(atPath: outCurrentEnc.path))

            // Case C: initial limits succeeds on sample #3, expires on sample #4 (currentLimits() in decodeOptions)
            let encodedPath = dir.appendingPathComponent("encoded-\(index).pb")
            try Data([0, 42]).write(to: encodedPath)
            let outCurrentDec = dir.appendingPathComponent("current-dec-\(index).bin")
            let argsCurrentDec = try Arguments([
                "decode", "-i", encodedPath.path, "--input-format", "packbits",
                "--decoded-bytes", "1", "--output-format", "raw", "-o", outCurrentDec.path
            ])
            try argsCurrentDec.validate()
            let scheduleCurrentDec = Mutex([before, before, before, expiredInstant])
            let controlCurrentDec = Control(seconds: 1.0, started: t0, now: {
                scheduleCurrentDec.withLock { list in
                    list.isEmpty ? expiredInstant : list.removeFirst()
                }
            })
            expectCLIExit(5) { try Main.run(argsCurrentDec, control: controlCurrentDec) }
            #expect(!FileManager.default.fileExists(atPath: outCurrentDec.path))
        }
    }
}
