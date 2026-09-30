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

    @Test func cancellationStopsPureLoopAtFuelCheckpoint() async throws {
        let runtime = CrabrixRuntime()
        let handle = try runtime.parse(bytes: [
            0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00,
            0x01, 0x04, 0x01, 0x60, 0x00, 0x00,
            0x03, 0x02, 0x01, 0x00,
            0x07, 0x0A, 0x01, 0x06, 0x5F, 0x73, 0x74, 0x61, 0x72, 0x74, 0x00, 0x00,
            0x0A, 0x09, 0x01, 0x07, 0x00, 0x03, 0x40, 0x0C, 0x00, 0x0B, 0x0B,
        ])
        let policy = try ExecutionPolicy(maximumMemoryBytes: 64 * 1024 * 1024,
                                         maximumTableElements: 4096, fuel: .max)
        let token = CancellationToken()
        let running = Task.detached {
            Result {
                let instance = try runtime.instantiate(handle,
                    store: runtime.makeStore(policy: policy, cancellation: token))
                let start = try #require(instance.exports[function: "_start"])
                _ = try start()
            }
        }
        try await Task.sleep(for: .milliseconds(20))
        token.cancel()
        let result = await running.value
        #expect(token.isCancelled)
        switch result {
        case .success: Issue.record("Infinite loop returned without a Stop trap")
        case let .failure(error): #expect((error as? Trap)?.isOutOfFuel == true)
        }
    }
}
