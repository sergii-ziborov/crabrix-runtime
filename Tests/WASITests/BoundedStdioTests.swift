import Foundation
import Testing
import WasmTypes
@_spi(WASIPlatform) @testable import WASI

@Suite struct BoundedStdioTests {
    @Test func stdoutAndStderrShareWriteBudget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let stdoutURL = root.appendingPathComponent("stdout")
        let stderrURL = root.appendingPathComponent("stderr")
        FileManager.default.createFile(atPath: stdoutURL.path, contents: nil)
        FileManager.default.createFile(atPath: stderrURL.path, contents: nil)
        let stdout = try FileHandle(forWritingTo: stdoutURL)
        let stderr = try FileHandle(forWritingTo: stderrURL)
        defer { try? stdout.close(); try? stderr.close() }

        let budget = try WASIOutputBudget(maximumBytes: 5)
        let bridge = try WASIBridgeToHost(
            stdout: stdout.fileDescriptor, stderr: stderr.fileDescriptor, outputBudget: budget
        )
        try bridge.runAndClose { bridge in
            let memory = TestSupport.TestGuestMemory()
            let wasi = bridge.underlying
            let first = memory.writeIOVecs([Array("abc".utf8)])
            #expect(try wasi.fd_write(fileDescriptor: 1, ioVectors: first, memory: memory) == 3)
            let second = memory.writeIOVecs([Array("de".utf8)])
            #expect(try wasi.fd_write(fileDescriptor: 2, ioVectors: second, memory: memory) == 2)
            let denied = memory.writeIOVecs([Array("f".utf8)])
            do {
                _ = try wasi.fd_write(fileDescriptor: 1, ioVectors: denied, memory: memory)
                Issue.record("a write past the shared limit succeeded")
            } catch let error as WASIAbi.Errno {
                #expect(error == .EFBIG)
            }
            #expect(budget.wasExceeded)
        }
        #expect(try String(contentsOf: stdoutURL, encoding: .utf8) == "abc")
        #expect(try String(contentsOf: stderrURL, encoding: .utf8) == "de")
    }

    @Test func positionedWritesAndTruncationCannotBypassBudget() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let outputURL = root.appendingPathComponent("output")
        FileManager.default.createFile(atPath: outputURL.path, contents: nil)
        let output = try FileHandle(forWritingTo: outputURL)
        defer { try? output.close() }
        let budget = try WASIOutputBudget(maximumBytes: 4)
        let file = BoundedStdioFile(fd: FileDescriptor(rawValue: output.fileDescriptor), budget: budget)
        let memory = TestSupport.TestGuestMemory()
        let vectors = memory.writeIOVecs([Array("x".utf8)])
        let buffers = GuestBuffers(iovs: vectors, memory: memory)

        do {
            _ = try file.pwrite(vectored: buffers, offset: 1_000_000)
            Issue.record("positioned write succeeded")
        } catch let error as WASIAbi.Errno {
            #expect(error == .ESPIPE)
        }
        do {
            _ = try file.seek(offset: 1_000_000, whence: .SET)
            Issue.record("seek succeeded")
        } catch let error as WASIAbi.Errno {
            #expect(error == .ESPIPE)
        }
        do {
            try file.setFilestatSize(1_000_000)
            Issue.record("truncate extension succeeded")
        } catch let error as WASIAbi.Errno {
            #expect(error == .EINVAL)
        }
        #expect(try Data(contentsOf: outputURL).isEmpty)
    }
}
