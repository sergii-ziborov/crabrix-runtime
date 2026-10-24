import Testing
import WAT
@_spi(Fuzzing) @testable import WasmKit

struct ProcMacroTransportTests {
    private func engine(_ model: EngineConfiguration.ThreadingModel) -> Engine {
        var config = EngineConfiguration(threadingModel: model, memoryBoundsChecking: .software, fuelMetering: true)
        config.enableExperimentalSoftwareDirectThreading()
        return Engine(configuration: config)
    }

    private func parent(requestPointer: UInt32 = 0, requestLength: UInt32 = 23) throws -> Module {
        try parseWasm(bytes: wat2wasm("""
        (module
          (import "crabrix_proc_macro_v1" "exchange" (func $exchange (param i32 i32 i32 i32 i32 i32) (result i32)))
          (import "crabrix_proc_macro_v1" "read_reply" (func $read (param i32 i32) (result i32)))
          (memory (export "memory") 1)
          (data (i32.const 0) "\\0a\\00\\00\\00macro.wasm\\05\\00\\00\\00decls")
          (func (export "__crabrix_pm_alloc") (param i32) (result i32) (i32.const 4096))
          (func (export "__crabrix_pm_free") (param i32 i32))
          (func (export "__crabrix_pm_dispatch") (param $p i32) (param i32) (result i64)
            (i32.store (i32.const 8192) (i32.add (i32.load (local.get $p)) (i32.const 35)))
            (i64.const 17179877376))
          (func (export "run") (result i32) (local $length i32)
            (local.set $length (call $exchange (i32.const 1) (i32.const 0) (i32.const 0)
              (i32.const \(requestPointer)) (i32.const \(requestLength)) (i32.const 0)))
            (drop (call $read (i32.const 128) (local.get $length)))
            (i32.store (i32.const 256) (i32.const 7))
            (local.set $length (call $exchange (i32.const 2) (i32.load (i32.const 132)) (i32.const 0)
              (i32.const 256) (i32.const 4) (i32.const 0)))
            (drop (call $read (i32.const 512) (local.get $length)))
            (i32.load (i32.const 512))))
        """))
    }

    private func child(spin: Bool = false, oversized: Bool = false) throws -> Module {
        try parseWasm(bytes: wat2wasm("""
        (module
          (import "crabrix_proc_macro_v1" "exchange" (func $exchange (param i32 i32 i32 i32 i32 i32) (result i32)))
          (import "crabrix_proc_macro_v1" "read_reply" (func $read (param i32 i32) (result i32)))
          (memory (export "memory") 1)
          (global (export "decls") i32 (i32.const 1024))
          (func (export "__crabrix_pm_alloc") (param i32) (result i32) (i32.const 4096))
          (func (export "__crabrix_pm_free") (param i32 i32))
          (func (export "__crabrix_pm_metadata") (param i32) (result i64)
            (i64.const \(oversized ? "72057598332895232" : "17179869440")))
          (func (export "__crabrix_pm_expand") (param i32 i32) (param $p i32) (param $n i32) (param i32)
            (result i64) (local $length i32)
            \(spin ? "(loop $loop (br $loop))" : "")
            (local.set $length (call $exchange (i32.const 3) (i32.const 0) (i32.const 0)
              (local.get $p) (local.get $n) (i32.const 0)))
            (drop (call $read (i32.const 8192) (local.get $length)))
            (i64.const 17179877376)))
        """))
    }

    @Test func realNestedStoreCallbacksPreserveBytesAndAggregateFuel() throws {
        for model in [EngineConfiguration.ThreadingModel.token, .direct] {
            let engine = engine(model), module = try child()
            let store = Store(engine: engine)
            store.fuel = Fuel(remaining: 10_000)
            var loads = 0
            let transport = ProcMacroTransport(engine: engine) { path, symbol, childStore, imports in
                #expect(path == "macro.wasm" && symbol == "decls")
                loads += 1
                return .init(instance: try module.instantiate(store: childStore, imports: imports))
            }
            defer { transport.close() }
            var imports = Imports()
            transport.link(to: &imports, store: store)
            let instance = try parent().instantiate(store: store, imports: imports)
            let run = try #require(instance.exports[function: "run"])
            #expect(try run() == [.i32(42)])
            let first = try #require(store.fuel).remaining
            #expect(first < 10_000)
            #expect(try run() == [.i32(42)])
            #expect(try #require(store.fuel).remaining < first)
            #expect(loads == 1)
        }
    }

    @Test func childCannotResetItsFuelWithRPCAndInfiniteLoopTraps() throws {
        for model in [EngineConfiguration.ThreadingModel.token, .direct] {
            let engine = engine(model), child = try child(spin: true)
            let store = Store(engine: engine)
            store.fuel = Fuel(remaining: 1_000)
            let transport = ProcMacroTransport(engine: engine) { _, _, store, imports in
                .init(instance: try child.instantiate(store: store, imports: imports))
            }
            defer { transport.close() }
            var imports = Imports(); transport.link(to: &imports, store: store)
            let instance = try parent().instantiate(store: store, imports: imports)
            let run = try #require(instance.exports[function: "run"])
            do {
                try run(); Issue.record("infinite macro was allowed to complete")
            } catch let trap as Trap { #expect(trap.isOutOfFuel) }
            #expect(try #require(store.fuel).remaining < 10)
        }
    }

    @Test func invalidPointersAndOversizedRepliesFailBeforeCopying() throws {
        let engine = engine(.token)
        for invalidPointer in [true, false] {
            let store = Store(engine: engine)
            store.fuel = Fuel(remaining: 10_000)
            let child = try child(oversized: true)
            var loads = 0
            let transport = ProcMacroTransport(engine: engine) { _, _, store, imports in
                loads += 1
                return .init(instance: try child.instantiate(store: store, imports: imports))
            }
            defer { transport.close() }
            var imports = Imports(); transport.link(to: &imports, store: store)
            let instance = try parent(requestPointer: invalidPointer ? .max : 0)
                .instantiate(store: store, imports: imports)
            let run = try #require(instance.exports[function: "run"])
            #expect(throws: ProcMacroTransport.Failure.self) { try run() }
            #expect(loads == (invalidPointer ? 0 : 1))
        }
    }

    @Test func recursiveMacroGetsFreshClientStateAndClosesItsStore() throws {
        for model in [EngineConfiguration.ThreadingModel.token, .direct] {
            let engine = engine(model)
            let child = try parseWasm(bytes: wat2wasm("""
            (module
              (import "crabrix_proc_macro_v1" "exchange" (func $exchange (param i32 i32 i32 i32 i32 i32) (result i32)))
              (import "crabrix_proc_macro_v1" "read_reply" (func $read (param i32 i32) (result i32)))
              (memory (export "memory") 1)
              (global (export "decls") i32 (i32.const 1024))
              (global $entered (mut i32) (i32.const 0))
              (func (export "__crabrix_pm_alloc") (param i32) (result i32) (i32.const 4096))
              (func (export "__crabrix_pm_free") (param i32 i32))
              (func (export "__crabrix_pm_metadata") (param i32) (result i64) (i64.const 17179869440))
              (func (export "__crabrix_pm_expand") (param i32 i32) (param $p i32) (param $n i32) (param i32)
                (result i64) (local $length i32)
                (if (global.get $entered) (then unreachable))
                (global.set $entered (i32.const 1))
                (local.set $length (call $exchange (i32.const 3) (i32.const 0) (i32.const 0)
                  (local.get $p) (local.get $n) (i32.const 0)))
                (drop (call $read (i32.const 8192) (local.get $length)))
                (global.set $entered (i32.const 0))
                (i64.const 17179877376)))
            """))
            let parent = try parseWasm(bytes: wat2wasm("""
            (module
              (import "crabrix_proc_macro_v1" "exchange" (func $exchange (param i32 i32 i32 i32 i32 i32) (result i32)))
              (import "crabrix_proc_macro_v1" "read_reply" (func $read (param i32 i32) (result i32)))
              (memory (export "memory") 1)
              (global $depth (mut i32) (i32.const 0))
              (data (i32.const 0) "\\0a\\00\\00\\00macro.wasm\\05\\00\\00\\00decls")
              (func (export "__crabrix_pm_alloc") (param i32) (result i32) (i32.const 4096))
              (func (export "__crabrix_pm_free") (param i32 i32))
              (func (export "__crabrix_pm_dispatch") (param $p i32) (param i32) (result i64) (local $length i32)
                (if (i32.eqz (global.get $depth))
                  (then
                    (global.set $depth (i32.const 1))
                    (i32.store (i32.const 16384) (i32.const 6))
                    (local.set $length (call $exchange (i32.const 2) (i32.const 1) (i32.const 0)
                      (i32.const 16384) (i32.const 4) (i32.const 0)))
                    (drop (call $read (i32.const 16388) (local.get $length)))
                    (i32.store (i32.const 8192) (i32.add (i32.load (i32.const 16388)) (i32.const 1)))
                    (global.set $depth (i32.const 0)))
                  (else (i32.store (i32.const 8192) (i32.add (i32.load (local.get $p)) (i32.const 35)))))
                (i64.const 17179877376))
              (func (export "run") (result i32) (local $length i32)
                (local.set $length (call $exchange (i32.const 1) (i32.const 0) (i32.const 0)
                  (i32.const 0) (i32.const 23) (i32.const 0)))
                (drop (call $read (i32.const 128) (local.get $length)))
                (i32.store (i32.const 256) (i32.const 7))
                (local.set $length (call $exchange (i32.const 2) (i32.const 1) (i32.const 0)
                  (i32.const 256) (i32.const 4) (i32.const 0)))
                (drop (call $read (i32.const 512) (local.get $length)))
                (i32.load (i32.const 512))))
            """))
            var loads = 0, closes = 0
            let transport = ProcMacroTransport(engine: engine) { _, _, store, imports in
                loads += 1
                return .init(instance: try child.instantiate(store: store, imports: imports), close: { closes += 1 })
            }
            let store = Store(engine: engine); store.fuel = Fuel(remaining: 10_000)
            var imports = Imports(); transport.link(to: &imports, store: store)
            let instance = try parent.instantiate(store: store, imports: imports)
            let run = try #require(instance.exports[function: "run"])
            #expect(try run() == [.i32(42)])
            #expect(loads == 2 && closes == 1)
            transport.close()
            #expect(closes == 2)
        }
    }
}
