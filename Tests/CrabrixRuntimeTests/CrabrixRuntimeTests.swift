import Testing
import CrabrixRuntime
import WasmKit

@Suite struct CrabrixRuntimeTests {
    @Test func freshStoresHaveIndependentFuel() throws {
        let runtime = CrabrixRuntime()
        let policy = try ExecutionPolicy(maximumMemoryBytes: 64 * 1024 * 1024, maximumTableElements: 4096, fuel: 42)
        let first = runtime.makeStore(policy: policy)
        let second = runtime.makeStore(policy: policy)
        first.fuel = Fuel(remaining: 3)
        #expect(first !== second)
        #expect(first.fuel?.remaining == 3)
        #expect(second.fuel?.remaining == 42)
    }

    @Test func emptyModuleParsesAndInstantiates() throws {
        let runtime = CrabrixRuntime()
        let handle = try runtime.parse(bytes: [0, 97, 115, 109, 1, 0, 0, 0])
        let policy = try ExecutionPolicy(maximumMemoryBytes: 64 * 1024 * 1024, maximumTableElements: 4096, fuel: 10)
        _ = try runtime.instantiate(handle, store: runtime.makeStore(policy: policy))
        #expect(handle.sourceByteCount == 8)
    }

    @Test func invalidLimitsFailClosed() {
        #expect(throws: RuntimeDiagnostic.invalidPolicy) {
            try ExecutionPolicy(maximumMemoryBytes: 0, maximumTableElements: 4096, fuel: 1)
        }
    }

    @Test func moduleInitialMemoryCannotExceedPolicy() throws {
        // A valid empty module with one memory requiring two 64 KiB pages.
        let runtime = CrabrixRuntime()
        let handle = try runtime.parse(bytes: [0, 97, 115, 109, 1, 0, 0, 0, 5, 3, 1, 0, 2])
        let policy = try ExecutionPolicy(maximumMemoryBytes: 65_536, maximumTableElements: 4096, fuel: 10)
        #expect(throws: RuntimeDiagnostic.memoryLimit) {
            try runtime.instantiate(handle, store: runtime.makeStore(policy: policy))
        }
    }
}
