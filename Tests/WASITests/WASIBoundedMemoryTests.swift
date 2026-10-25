import Testing
import WasmTypes
import WasmKit
@_spi(WASIPlatform) @testable import WASI

@Suite struct WASIBoundedMemoryTests {
    final class Memory: GuestMemory {
        var bytes: [UInt8]
        var views = 0
        var guestMemoryByteCount: Int? { bytes.count }
        init(_ count: Int = 64) { bytes = Array(repeating: 0, count: count) }
        func withUnsafeMutableBufferPointer<T>(offset: UInt, count: Int,
            _ body: (UnsafeMutableRawBufferPointer) throws -> T) rethrows -> T {
            // A failed validator would abort this test process rather than
            // merely satisfy an expectation with a synthetic host result.
            precondition(count >= 0 && offset <= bytes.count && count <= bytes.count - Int(offset))
            views += 1
            return try bytes.withUnsafeMutableBytes { raw in
                try body(UnsafeMutableRawBufferPointer(rebasing: raw[Int(offset)..<Int(offset) + count]))
            }
        }
    }

    @Test func rejectsUnaddressableBuffersAcrossPreview1Capabilities() throws {
        let bridge = try WASIBridgeToHost(args: ["test"], environment: ["A": "B"], fileSystem: .memory(MemoryFileSystem()))
        defer { try? bridge.close() }
        let functions = bridge.hostFunctions(capabilities: WASICapability<Memory>.all)
        let bad = Value.i32(.max)
        let cases: [(String, [Value])] = [
            ("args_get", [bad, .i32(0)]), ("environ_get", [.i32(0), bad]),
            ("args_sizes_get", [.i32(0), bad]), ("environ_sizes_get", [bad, .i32(0)]),
            ("clock_res_get", [.i32(0), bad]), ("clock_time_get", [.i32(0), .i64(0), bad]),
            ("random_get", [bad, .i32(1)]),
            ("fd_write", [.i32(1), bad, .i32(1), .i32(32)]),
            ("fd_pread", [.i32(0), bad, .i32(1), .i64(0), .i32(32)]),
            ("fd_fdstat_get", [.i32(0), bad]), ("fd_filestat_get", [.i32(0), bad]),
            ("fd_prestat_get", [.i32(3), bad]), ("fd_prestat_dir_name", [.i32(3), bad, .i32(1)]),
            ("fd_seek", [.i32(0), .i64(0), .i32(0), bad]),
            ("fd_tell", [.i32(0), bad]),
            ("path_open", [.i32(3), .i32(0), bad, .i32(1), .i32(0), .i64(0), .i64(0), .i32(0), .i32(32)]),
            ("path_readlink", [.i32(3), bad, .i32(1), .i32(0), .i32(1), .i32(32)]),
            ("path_symlink", [bad, .i32(1), .i32(3), .i32(0), .i32(1)]),
            ("poll_oneoff", [bad, .i32(0), .i32(1), .i32(32)]),
        ]
        for (name, values) in cases {
            let memory = Memory()
            let function = try #require(functions[name])
            #expect(try function.implementation(memory, values) == [.i32(UInt32(WASIAbi.Errno.EFAULT.rawValue))], "\(name)")
            #expect(memory.views == 0, "\(name) read guest memory before rejecting the range")
        }
    }

    @Test func checksNestedVectorsAndCapsWorkBeforeWalkingAnAttackerList() throws {
        let bridge = try WASIBridgeToHost(fileSystem: .memory(MemoryFileSystem()))
        defer { try? bridge.close() }
        let write = try #require(bridge.hostFunctions(capabilities: WASICapability<Memory>.all)["fd_write"])
        let nested = Memory()
        nested.bytes.replaceSubrange(0..<8, with: [255, 255, 255, 255, 4, 0, 0, 0])
        #expect(try write.implementation(nested, [.i32(1), .i32(0), .i32(1), .i32(32)])
                == [.i32(UInt32(WASIAbi.Errno.EFAULT.rawValue))])
        #expect(nested.views == 1)
        let oversized = Memory(16_384)
        #expect(try write.implementation(oversized, [.i32(1), .i32(0), .i32(1025), .i32(16_000)])
                == [.i32(UInt32(WASIAbi.Errno.EINVAL.rawValue))])
        #expect(oversized.views == 0)
    }

    @Test func validArgumentWritesKeepTheirExactBytes() throws {
        let bridge = try WASIBridgeToHost(args: ["test"], environment: ["A": "B"], fileSystem: .memory(MemoryFileSystem()))
        defer { try? bridge.close() }
        let functions = bridge.hostFunctions(capabilities: WASICapability<Memory>.all)
        let memory = Memory()
        #expect(try #require(functions["args_sizes_get"]).implementation(memory, [.i32(8), .i32(12)]) == [.i32(0)])
        #expect(Array(memory.bytes[8..<16]) == [1, 0, 0, 0, 5, 0, 0, 0])
        #expect(try #require(functions["args_get"]).implementation(memory, [.i32(0), .i32(32)]) == [.i32(0)])
        #expect(Array(memory.bytes[32..<37]) == Array("test\0".utf8))
    }

    @Test func emptyRealMemoryAllowsAnEmptyViewAndRejectsHostWrites() throws {
        let store = Store(engine: Engine())
        let memory = try WasmKit.Memory(store: store, type: MemoryType(min: 0, max: 1))
        #expect(memory.guestMemoryByteCount == 0)
        let count = memory.withUnsafeMutableBufferPointer(offset: 0, count: 0) { $0.count }
        #expect(count == 0)
        let bridge = try WASIBridgeToHost(args: ["test"], fileSystem: .memory(MemoryFileSystem()))
        defer { try? bridge.close() }
        let function = try #require(bridge.hostFunctions(capabilities: WASICapability<WasmKit.Memory>.all)["args_sizes_get"])
        #expect(try function.implementation(memory, [.i32(0), .i32(0)])
                == [.i32(UInt32(WASIAbi.Errno.EFAULT.rawValue))])
    }
}
