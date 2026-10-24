import Foundation
import Testing
import WAT
@_spi(Fuzzing) @testable import WasmKit

@Suite(.enabled(if: ProcessInfo.processInfo.environment["CRABRIX_RUN_EXPERIMENTAL_DIRECT"] == "1"))
struct ExperimentalDirectSoftwareTests {
    private func engine(threadingModel: EngineConfiguration.ThreadingModel = .direct) -> Engine {
        var configuration = EngineConfiguration(threadingModel: threadingModel,
            memoryBoundsChecking: .software, fuelMetering: true,
            softwareMemoryReservationBytes: 4 * 65_536)
        configuration.enableExperimentalSoftwareDirectThreading()
        return Engine(configuration: configuration)
    }

    @Test func probeInstalledByHostCallStopsBeforeTheNextLoopBody() throws {
        final class Cancelled: ExecutionCancellation, @unchecked Sendable {
            var calls = 0
            var isCancelled: Bool { calls += 1; return true }
        }
        let module = try parseWasm(bytes: wat2wasm("""
            (module
              (import "host" "cancel" (func $cancel))
              (memory 1)
              (func (export "spin")
                (call $cancel)
                (loop $loop
                  (i32.store (i32.const 0)
                    (i32.add (i32.load (i32.const 0)) (i32.const 1)))
                  (br $loop)))
              (func (export "read") (result i32) (i32.load (i32.const 0))))
            """))
        for model in [EngineConfiguration.ThreadingModel.token, .direct] {
            let store = Store(engine: engine(threadingModel: model))
            store.fuel = Fuel(remaining: 1_000_000)
            let probe = Cancelled()
            var imports = Imports()
            imports.define(module: "host", name: "cancel",
                Function(store: store, parameters: [], results: []) { caller, _ in
                    caller.store.cancellationProbe = probe
                    return []
                })
            let instance = try module.instantiate(store: store, imports: imports)
            let spin = try #require(instance.exports[function: "spin"])
            #expect(throws: Trap.self) { try spin() }
            #expect(probe.calls == 1)
            store.cancellationProbe = nil
            let read = try #require(instance.exports[function: "read"])
            #expect(try read() == [.i32(0)])
        }
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

    @Test func cancellationAndCommittedMemoryBoundsRemainEffective() throws {
        final class Probe: ExecutionCancellation, @unchecked Sendable {
            var calls = 0
            var isCancelled: Bool { calls += 1; return calls >= 2 }
        }
        let module = try parseWasm(bytes: wat2wasm("""
            (module (memory 1 4)
              (func (export "read") (result i32) (i32.load (i32.const 65536)))
              (func (export "grow") (result i32) (memory.grow (i32.const 1)))
              (func (export "spin") (loop $loop (br $loop))))
            """))
        let store = Store(engine: engine())
        store.fuel = Fuel(remaining: 1_000_000)
        let instance = try module.instantiate(store: store)
        let read = try #require(instance.exports[function: "read"])
        let grow = try #require(instance.exports[function: "grow"])
        #expect(throws: Trap.self) { try read() }
        let grown = try grow()
        #expect(grown == [.i32(1)])
        let zero = try read()
        #expect(zero == [.i32(0)])
        let probe = Probe()
        store.cancellationProbe = probe
        let fuelBeforeLoop = try #require(store.fuel).remaining
        let spin = try #require(instance.exports[function: "spin"])
        #expect(throws: Trap.self) { try spin() }
        #expect(probe.calls == 2)
        let fuelAfterLoop = try #require(store.fuel).remaining
        #expect(fuelBeforeLoop - fuelAfterLoop < 1_000)
        store.cancellationProbe = nil
        let afterCancel = try read()
        #expect(afterCancel == [.i32(0)])
    }
}
