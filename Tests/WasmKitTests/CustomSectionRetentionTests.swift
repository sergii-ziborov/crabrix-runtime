import Foundation
import Testing
import WAT
@testable import WasmKit

@Suite struct CustomSectionRetentionTests {
    private func leb(_ count: Int) -> [UInt8] {
        var n = count, bytes: [UInt8] = []
        repeat {
            let low = UInt8(n & 127)
            n >>= 7
            bytes.append(low | (n == 0 ? 0 : 128))
        } while n != 0
        return bytes
    }

    private func custom(_ name: String, _ contents: [UInt8]) -> [UInt8] {
        let body = leb(name.utf8.count) + Array(name.utf8) + contents
        return [0] + leb(body.count) + body
    }

    @Test func discardingDebugKeepsOtherCustomSectionsAndExecutableCode() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wasm")
        defer { try? FileManager.default.removeItem(at: url) }
        let code = try wat2wasm("(module (func (export \"answer\") (result i32) i32.const 42))")
        let bytes = code + custom("name", [])
            + custom(".debug_info", Array(repeating: 7, count: 256 * 1024))
            + custom("producers", [1, 2, 3])
        try Data(bytes).write(to: url)
        let original = try parseWasm(filePath: url.path)
        #expect(original.customSections.contains { $0.name == ".debug_info" && $0.bytes.count == 256 * 1024 })
        let filtered = try parseWasm(filePath: url.path, retainDebugCustomSections: false)
        #expect(filtered.customSections.map(\.name) == ["producers"])
        #expect(Array(filtered.customSections[0].bytes) == [1, 2, 3])
        let instance = try filtered.instantiate(store: Store(engine: Engine()))
        #expect(try instance.exports[function: "answer"]?([]) == [.i32(42)])
    }

    @Test func discardedSectionsStillRejectTruncatedPayloads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wasm")
        defer { try? FileManager.default.removeItem(at: url) }
        var bytes = try wat2wasm("(module)") + custom(".debug_info", Array(repeating: 0, count: 200_000))
        bytes.removeLast()
        try Data(bytes).write(to: url)
        #expect(throws: (any Error).self) {
            try parseWasm(filePath: url.path, retainDebugCustomSections: false)
        }
    }

    @Test func compilerParseBenchmark() throws {
        guard let path = ProcessInfo.processInfo.environment["CRABRIX_PARSER_BENCHMARK_WASM"] else { return }
        let retain = ProcessInfo.processInfo.environment["CRABRIX_PARSER_RETAIN_DEBUG"] != "0"
        let start = ContinuousClock.now
        let module = try parseWasm(filePath: path, retainDebugCustomSections: retain)
        let duration = start.duration(to: .now)
        print("CRABRIX_PARSER_BENCHMARK retainDebug=\(retain) duration=\(duration) retainedCustomBytes=\(module.customSections.reduce(0) { $0 + $1.bytes.count })")
        #expect(!module.exports.isEmpty)
    }
}
