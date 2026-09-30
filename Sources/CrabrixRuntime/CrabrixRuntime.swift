import Foundation
@_spi(Fuzzing) import WasmKit

/// Provenance of the engine and the app-selected revision of this fork.
public struct RuntimeIdentity: Equatable, Sendable {
    public static let upstreamCommit = "a0471eaee817c523b8023d8ebb1c70ff70b7950a"
    public let forkRevision: String

    public init(forkRevision: String) {
        self.forkRevision = forkRevision
    }
}

/// Hard limits for one fresh Store. Callers provide compiler and program values separately.
public struct ExecutionPolicy: Equatable, Sendable {
    public let maximumMemoryBytes: Int
    public let maximumTableElements: Int
    public let fuel: UInt64

    public init(maximumMemoryBytes: Int, maximumTableElements: Int, fuel: UInt64) throws {
        guard maximumMemoryBytes > 0, maximumTableElements > 0, fuel > 0 else {
            throw RuntimeDiagnostic.invalidPolicy
        }
        self.maximumMemoryBytes = maximumMemoryBytes
        self.maximumTableElements = maximumTableElements
        self.fuel = fuel
    }
}

public enum RuntimeDiagnostic: Error, Equatable, Sendable {
    case invalidPolicy
    case memoryLimit
    case tableLimit
}

/// Thread-safe user Stop signal, checked by WasmKit's existing fuel checkpoints.
public final class CancellationToken: ExecutionCancellation, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool { lock.withLock { cancelled } }

    public func cancel() { lock.withLock { cancelled = true } }
}

/// Parsed code only. No Store, instance, memory, descriptor, or mutable global is cached here.
public struct ModuleHandle: Sendable {
    let module: Module
    public let sourceByteCount: Int

    init(module: Module, sourceByteCount: Int) {
        self.module = module
        self.sourceByteCount = sourceByteCount
    }
}

/// A narrow embedding entry point around WasmKit 0.4.1. WASI belongs to the
/// caller's per-execution session; this object never retains it.
public final class CrabrixRuntime: @unchecked Sendable {
    private let engine: Engine

    public init() {
        let configuration = EngineConfiguration(
            threadingModel: .token,
            compilationMode: .lazy,
            stackSize: 16 * 1024 * 1024,
            memoryBoundsChecking: .software,
            fuelMetering: true
        )
        engine = Engine(configuration: configuration)
    }

    public func parse(bytes: [UInt8]) throws -> ModuleHandle {
        ModuleHandle(module: try parseWasm(bytes: bytes), sourceByteCount: bytes.count)
    }

    /// Every invocation receives a fresh Store. Upstream fuel is the sole
    /// instruction budget; Crabrix's former 4096-instruction limiter is absent.
    public func makeStore(policy: ExecutionPolicy, cancellation: CancellationToken? = nil) -> Store {
        let store = Store(engine: engine)
        store.resourceLimiter = CrabrixResourceLimiter(policy: policy)
        store.fuel = Fuel(remaining: policy.fuel)
        store.cancellationProbe = cancellation
        return store
    }

    public func instantiate(_ handle: ModuleHandle, store: Store, imports: Imports = [:]) throws -> Instance {
        try handle.module.instantiate(store: store, imports: imports)
    }
}

private final class CrabrixResourceLimiter: ResourceLimiter {
    let policy: ExecutionPolicy

    init(policy: ExecutionPolicy) {
        self.policy = policy
    }

    func limitMemoryGrowth(to desired: Int) throws -> Bool {
        if desired > policy.maximumMemoryBytes { throw RuntimeDiagnostic.memoryLimit }
        return true
    }

    func limitTableGrowth(to desired: Int) throws -> Bool {
        if desired > policy.maximumTableElements { throw RuntimeDiagnostic.tableLimit }
        return true
    }
}
