import Foundation
import Testing
import WAT
@_spi(Fuzzing) @testable import WasmKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRABRIX_RUN_EXPERIMENTAL_DIRECT"] == "1"))
struct ExperimentalDirectSoftwareTests {
    private func engine() -> Engine {
        var configuration = EngineConfiguration(threadingModel: .direct,
            memoryBoundsChecking: .software, fuelMetering: true,
            softwareMemoryReservationBytes: 4 * 65_536)
        configuration.enableExperimentalSoftwareDirectThreading()
        return Engine(configuration: configuration)
    }

    @Test func outOfBoundsAndExplicitTrapsPropagate() throws {
        let engine = engine()
        guard case .direct = engine.configuration.threadingModel else {
            Issue.record("experimental direct request was not enabled"); return
        }
        for operation in ["i32.load (i32.const 65536)",
                          "i32.wrap_i64 (i64.load (i32.const 65532))",
                          "i32.div_s (i32.const 1) (i32.const 0)",
                          "unreachable"] {
            let module = try parseWasm(bytes: wat2wasm("""
                (module (memory 1 4)
                  (func (export "bad") (result i32) (\(operation)))
                  (func (export "good") (result i32) (i32.const 42)))
                """))
            let store = Store(engine: engine)
            store.fuel = Fuel(remaining: 1_000)
            let instance = try module.instantiate(store: store)
            let bad = try #require(instance.exports[function: "bad"])
            #expect(throws: Trap.self) { try bad() }
            let good = try #require(instance.exports[function: "good"])
            let result = try good()
            #expect(result == [.i32(42)])
        }
    }

    @Test func fuelStopsALoopAndAllowsRecovery() throws {
        let module = try parseWasm(bytes: wat2wasm("""
            (module (func (export "spin") (loop $loop (br $loop)))
              (func (export "good") (result i32) (i32.const 42)))
            """))
        let store = Store(engine: engine())
        store.fuel = Fuel(remaining: 10)
        let instance = try module.instantiate(store: store)
        let spin = try #require(instance.exports[function: "spin"])
        #expect(throws: Trap.self) { try spin() }
        store.fuel = Fuel(remaining: 100)
        let good = try #require(instance.exports[function: "good"])
        let result = try good()
        #expect(result == [.i32(42)])
    }
}
