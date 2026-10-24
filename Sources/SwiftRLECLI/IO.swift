// SPDX-License-Identifier: Apache-2.0
import Foundation
import SwiftRLE
import Synchronization
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

let receivedSignal = Atomic<Int32>(0)

final class Control: Sendable {
    let cancelled = Atomic<Bool>(false)
    let started = ContinuousClock.now
    let deadline: ContinuousClock.Instant
    init(seconds: Double) { deadline = started.advanced(by:.seconds(seconds)) }
    func check() throws { if receivedSignal.load(ordering:.relaxed) != 0 || cancelled.load(ordering:.relaxed) { throw CLIError(130) }; if ContinuousClock.now >= deadline { throw CLIError(5) } }
}
struct StreamIO {
    let control: Control
    func ready(_ fd: Int32, _ event: Int16) throws {
        while true {
            try control.check()
            var item = pollfd(fd:fd,events:event,revents:0)
            let result = poll(&item,1,20)
            if result > 0 { return }
            if result < 0 && errno != EINTR { throw CLIError(6) }
        }
    }
    func readInput(_ path: String, maximum: Int) throws -> Data {
        let fd = path == "-" ? STDIN_FILENO : open(path,O_RDONLY | O_NONBLOCK)
        guard fd >= 0 else { throw CLIError(6) }
        let original = fcntl(fd,F_GETFL); _ = fcntl(fd,F_SETFL,original | O_NONBLOCK)
        defer { if path != "-" { close(fd) } else { _ = fcntl(fd,F_SETFL,original) } }
        var result = Data(), chunk = [UInt8](repeating:0,count:16_384)
        while true {
            try ready(fd,Int16(POLLIN))
            let n = chunk.withUnsafeMutableBytes { read(fd,$0.baseAddress,$0.count) }
            if n == 0 { return result }
            if n < 0 { if errno == EINTR || errno == EAGAIN { continue }; throw CLIError(6) }
            guard n <= maximum - result.count else { throw CLIError(5) }
            result.append(contentsOf:chunk.prefix(n))
        }
    }
    func writeBytes(_ data: Data, fd: Int32) throws {
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                try ready(fd,Int16(POLLOUT))
                let n = write(fd,bytes.baseAddress?.advanced(by:offset),min(16_384,bytes.count-offset))
                if n < 0 { if errno == EINTR || errno == EAGAIN { continue }; throw CLIError(6) }
                guard n > 0 else { throw CLIError(6) }; offset += n
            }
        }
        try control.check()
    }
    func publish(_ pieces: [Data], path: String, overwrite: Bool) throws {
        if path == "-" {
            let original = fcntl(STDOUT_FILENO,F_GETFL); _ = fcntl(STDOUT_FILENO,F_SETFL,original | O_NONBLOCK)
            defer { _ = fcntl(STDOUT_FILENO,F_SETFL,original) }
            for piece in pieces { try writeBytes(piece,fd:STDOUT_FILENO) }; return
        }
        let url = URL(fileURLWithPath:path), temporary = url.deletingLastPathComponent().appendingPathComponent(".swiftrle-\(UUID().uuidString).tmp").path
        let fd = open(temporary,O_WRONLY | O_CREAT | O_EXCL | O_NONBLOCK,0o600)
        guard fd >= 0 else { throw CLIError(6) }
        defer { close(fd); unlink(temporary) }
        for piece in pieces { try writeBytes(piece,fd:fd) }
        guard fsync(fd) == 0 else { throw CLIError(6) }; try control.check()
        // link() is an atomic no-replace publication even against a competing creator.
        if overwrite { guard rename(temporary,path) == 0 else { throw CLIError(6) } }
        else { guard link(temporary,path) == 0 else { throw CLIError(6) } }
    }
}
