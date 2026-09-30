import Foundation
import Testing
import WAT
import WasmParser

@testable import WasmKit

/// Fuel metering charges a fixed price per Wasm operator, summed per region and charged at the
/// region's head. These tests pin the exact remaining fuel for small modules: the point of pricing
/// operators rather than translated instructions is that the numbers stay put, so a change that
/// moves them should fail here and be explained, not re-blessed.
@Suite
struct FuelTests {
    private final class CountingCancellation: ExecutionCancellation, @unchecked Sendable {
        private let lock = NSLock()
        private let stopAfter: Int?
        private var reads = 0

        init(stopAfter: Int? = nil) { self.stopAfter = stopAfter }

        var isCancelled: Bool {
            lock.lock()
            defer { lock.unlock() }
            reads += 1
            return stopAfter.map { reads >= $0 } ?? false
        }

        var readCount: Int { lock.withLock { reads } }
    }

    private static let countedLoop = """
        (module (func (export "f") (param i32) (result i32)
            (loop $l
                (local.set 0 (i32.sub (local.get 0) (i32.const 1)))
                (br_if $l (local.get 0)))
            (local.get 0)))
        """

    /// Instantiates `wat` on an engine with fuel metering enabled.
    private static func setUp(
        _ wat: String,
        fuel: UInt64?,
        compilationMode: EngineConfiguration.CompilationMode = .eager,
        threadingModel: EngineConfiguration.ThreadingModel? = nil,
        fuelMetering: Bool = true,
        features: WasmFeatureSet = .default
    ) throws -> (Store, Function) {
        let module = try parseWasm(bytes: wat2wasm(wat, features: features), features: features)
        let engine = Engine(
            configuration: EngineConfiguration(
                threadingModel: threadingModel,
                compilationMode: compilationMode,
                features: features,
                fuelMetering: fuelMetering
            )
        )
        let store = Store(engine: engine)
        if let fuel {
            store.fuel = Fuel(remaining: fuel)
        }
        let instance = try module.instantiate(store: store)
        let function = try #require(instance.exports[function: "f"])
        return (store, function)
    }

    /// Runs `wat`'s exported `f` with a large budget and returns the fuel it consumed.
    private static func consumed(
        _ wat: String,
        arguments: [Value] = [],
        budget: UInt64 = 1_000_000,
        compilationMode: EngineConfiguration.CompilationMode = .eager,
        threadingModel: EngineConfiguration.ThreadingModel? = nil,
        features: WasmFeatureSet = .default,
        expectTrap: Bool = false
    ) throws -> UInt64 {
        let (store, f) = try setUp(
            wat, fuel: budget, compilationMode: compilationMode, threadingModel: threadingModel,
            features: features)
        if expectTrap {
            #expect(throws: Trap.self) { try f(arguments) }
        } else {
            _ = try f(arguments)
        }
        let remaining = try #require(store.fuel).remaining
        return budget - remaining
    }

    // MARK: Exact costs

    // MARK: Bulk operations

    // MARK: Running out

    @Test
    func runawayLoopStopsAndLeavesTheBudgetUntouched() throws {
        let (store, f) = try Self.setUp(
            """
            (module (func (export "f") (loop $l (br $l))))
            """,
            fuel: 10
        )
        #expect(throws: Trap.self) { try f([]) }
        // 10 budget, 1 per trip through the loop's `br`: the tenth charge fails, and a failed
        // charge deducts nothing, so a caller can top up and retry the very same charge.
        #expect(try #require(store.fuel).remaining == 0)
    }

    @Test
    func storeIsUsableAfterRunningOut() throws {
        let (store, f) = try Self.setUp(
            """
            (module (func (export "f") (param i32 i32) (result i32)
                (i32.add (local.get 0) (local.get 1))))
            """,
            fuel: 2
        )
        #expect(throws: Trap.self) { try f([.i32(1), .i32(2)]) }
        store.fuel = Fuel(remaining: 100)
        let results = try f([.i32(1), .i32(2)])
        #expect(results == [.i32(3)])
        #expect(try #require(store.fuel).remaining == 97)
    }

    @Test
    func exhaustionIsReportedAsAnOutOfFuelTrap() throws {
        let (_, f) = try Self.setUp(
            """
            (module (func (export "f") (loop $l (br $l))))
            """,
            fuel: 5
        )
        do {
            _ = try f([])
            Issue.record("expected the guest to run out of fuel")
        } catch let trap as Trap {
            #expect(trap.description.contains("out of fuel"))
        }
    }

    // MARK: Configuration

    @Test(arguments: [EngineConfiguration.ThreadingModel.token, .direct])
    func cancellationPollingDoesNotChangeFuelOrResult(
        threadingModel: EngineConfiguration.ThreadingModel
    ) throws {
        func run(interval: UInt8) throws -> (reads: Int, remainingFuel: UInt64) {
            let (store, f) = try Self.setUp(
                Self.countedLoop, fuel: 1_000_000, threadingModel: threadingModel)
            let probe = CountingCancellation()
            store.cancellationProbe = probe
            store.cancellationPollInterval = interval
            #expect(try f([.i32(1_000)]) == [.i32(0)])
            return (probe.readCount, try #require(store.fuel).remaining)
        }

        let everyCheckpoint = try run(interval: 1)
        let everySixteenth = try run(interval: 16)
        #expect(everyCheckpoint.reads > 16)
        #expect(everySixteenth.reads < everyCheckpoint.reads)
        #expect(everySixteenth.remainingFuel == everyCheckpoint.remainingFuel)
    }

    @Test(arguments: [EngineConfiguration.ThreadingModel.token, .direct])
    func cancellationIsObservedWithinTheConfiguredInterval(
        threadingModel: EngineConfiguration.ThreadingModel
    ) throws {
        let (store, f) = try Self.setUp(
            Self.countedLoop, fuel: 1_000_000, threadingModel: threadingModel)
        let probe = CountingCancellation(stopAfter: 2)
        store.cancellationProbe = probe
        store.cancellationPollInterval = 16
        #expect(throws: Trap.self) { try f([.i32(1_000)]) }
        #expect(probe.readCount == 2)
        #expect(try #require(store.fuel).remaining > 0)
    }

    @Test
    func budgetIsUnlimitedByDefault() throws {
        let (store, f) = try Self.setUp(
            """
            (module (func (export "f") (param i32 i32) (result i32)
                (i32.add (local.get 0) (local.get 1))))
            """,
            fuel: nil
        )
        #expect(store.fuel == nil)
        _ = try f([.i32(1), .i32(2)])
        #expect(store.fuel == nil)
    }

    @Test
    func budgetIsInertWithoutFuelMetering() throws {
        // Documented behavior: setting a budget on an engine that does not meter fuel is accepted
        // and nothing consumes it.
        let (store, f) = try Self.setUp(
            """
            (module (func (export "f") (loop $l (br_if $l (i32.const 0)))))
            """,
            fuel: 3,
            fuelMetering: false
        )
        _ = try f([])
        #expect(try #require(store.fuel).remaining == 3)
    }

    @Test
    func budgetCanBeToppedUpInPlace() throws {
        let (store, _) = try Self.setUp(
            """
            (module (func (export "f")))
            """,
            fuel: 10
        )
        store.fuel?.remaining += 500
        #expect(try #require(store.fuel).remaining == 510)
    }

    // MARK: Escaping the budget
    //
    // The catalogue of loop shapes that must not escape a budget lives in
    // Tests/WasmKitTests/ExtraSuite/fuel/out_of_fuel.wast, where each case is data rather than
    // Swift and the spectest suite runs it under both threading models. What stays here are the
    // cases that need the embedder API: a host function, or an assertion about the counter itself.

    // MARK: Adversarial accounting

    @Test
    func hostFunctionCanDrainTheBudget() throws {
        let module = try parseWasm(
            bytes: wat2wasm(
                """
                (module
                    (import "env" "burn" (func $burn))
                    (func (export "f") (call $burn) (loop $l (br $l))))
                """))
        let engine = Engine(configuration: EngineConfiguration(fuelMetering: true))
        let store = Store(engine: engine)
        store.fuel = Fuel(remaining: 1_000_000)
        var imports = Imports()
        imports.define(
            module: "env", name: "burn",
            Function(store: store, parameters: [], results: []) { caller, _ in
                caller.store.fuel = Fuel(remaining: 0)
                return []
            })
        let instance = try module.instantiate(store: store, imports: imports)
        let f = try #require(instance.exports[function: "f"])
        #expect(throws: Trap.self) { try f([]) }
        #expect(try #require(store.fuel).remaining == 0)
    }

    @Test
    func aSingleUnitOfFuelDoesNotUnderflow() throws {
        let (store, f) = try Self.setUp(
            """
            (module (func (export "f") (param i32 i32) (result i32)
                (i32.add (local.get 0) (local.get 1))))
            """,
            fuel: 1
        )
        #expect(throws: Trap.self) { try f([.i32(1), .i32(2)]) }
        // The charge was 3 against a budget of 1. Nothing is deducted by a charge that fails, so
        // the counter neither goes negative nor wraps around to a huge value.
        #expect(try #require(store.fuel).remaining == 1)
    }

    @Test
    func hugeBulkLengthCannotUnderchargeByOverflowing() throws {
        // A length whose byte count overflows 64 bits must not wrap into a small charge. The copy
        // itself fails its bounds check, so the operator price is all that may be taken.
        let consumed = try Self.consumed(
            """
            (module (memory i64 1) (func (export "f")
                (memory.fill (i64.const 0) (i32.const 7) (i64.const 0x4000000000000000))))
            """,
            features: [.referenceTypes, .exceptionHandling, .memory64],
            expectTrap: true
        )
        #expect(consumed == 4)
    }

    // MARK: Both dispatch paths and both compilation modes agree

    @Test(arguments: [EngineConfiguration.CompilationMode.eager, .lazy])
    func costsAreIndependentOfCompilationMode(mode: EngineConfiguration.CompilationMode) throws {
        // Translation is deliberately not metered: the translated code is cached on the engine, so
        // charging for it would make the same call cost different amounts in different stores.
        let consumed = try Self.consumed(
            """
            (module (func (export "f") (param i32 i32) (result i32)
                (i32.add (local.get 0) (local.get 1))))
            """,
            arguments: [.i32(1), .i32(2)],
            compilationMode: mode
        )
        #expect(consumed == 3)
    }
}
