/// Host transport for Crabrix's versioned Rust proc-macro RPC bridge.
///
/// The loader is caller-owned: it must restrict paths to declared compiler
/// inputs and supply only the permitted WASI imports. The transport supplies
/// separate stores, bounded byte transfers, reentrant RPC and one fuel budget
/// shared by the compiler and all macros. It never loads native libraries.
public final class ProcMacroTransport {
    public struct LoadedModule {
        public let instance: Instance
        public let close: () -> Void
        public init(instance: Instance, close: @escaping () -> Void = {}) {
            self.instance = instance
            self.close = close
        }
    }
    public typealias Loader = (String, String, Store, inout Imports) throws -> LoadedModule

    public enum Failure: Error, Equatable {
        case invalidRequest
        case messageTooLarge
        case missingExport(String)
        case inactiveDispatcher
        case moduleLimit
        case depthLimit
        case unconsumedReply
        case unavailable
    }

    private final class Context {
        let moduleID: UInt32
        var reply: [UInt8]?
        init(moduleID: UInt32) { self.moduleID = moduleID }
    }

    private struct Guest {
        let loaded: LoadedModule
        let path: String
        let symbol: String
        let declarations: UInt32
        var instance: Instance { loaded.instance }
    }

    private struct ActiveCall {
        let moduleID: UInt32
        let parent: Instance
    }

    private final class MacroLimiter: ResourceLimiter, @unchecked Sendable {
        let memoryLimit: Int
        init(memoryLimit: Int) { self.memoryLimit = memoryLimit }
        func limitMemoryGrowth(to desired: Int) -> Bool { desired <= memoryLimit }
        func limitTableGrowth(to desired: Int) -> Bool { desired <= 100_000 }
    }

    private let engine: Engine
    private let loader: Loader
    private let maximumMessageBytes: Int
    private let maximumModules: Int
    private let memoryPerModule: Int
    private let maximumDepth: Int
    private var guests: [UInt32: Guest] = [:]
    private var identities: [String: UInt32] = [:]
    private var active: [ActiveCall] = []
    private var closed = false
    private var transientStores = 0

    public init(
        engine: Engine, maximumMessageBytes: Int = 16 * 1024 * 1024,
        maximumModules: Int = 8, memoryPerModule: Int = 64 * 1024 * 1024,
        maximumDepth: Int = 16, loader: @escaping Loader
    ) {
        precondition(maximumMessageBytes > 0 && maximumMessageBytes <= 16 * 1024 * 1024)
        precondition(maximumModules > 0 && memoryPerModule > 0 && maximumDepth > 0)
        self.engine = engine
        self.maximumMessageBytes = maximumMessageBytes
        self.maximumModules = maximumModules
        self.memoryPerModule = memoryPerModule
        self.maximumDepth = maximumDepth
        self.loader = loader
    }

    /// Retain this transport until execution finishes, then call close.
    public func link(to imports: inout Imports, store: Store) {
        link(to: &imports, store: store, context: Context(moduleID: 0))
    }

    /// proc_macro2 may link the API while using its ordinary parser fallback
    /// outside a macro expansion. Resolve the ABI without granting a loader.
    public static func linkUnavailable(to imports: inout Imports, store: Store) {
        for (name, count) in [("exchange", 6), ("read_reply", 2)] {
            imports.define(module: "crabrix_proc_macro_v1", name: name,
                Function(store: store, parameters: Array(repeating: .i32, count: count), results: [.i32]) { _, _ in
                    throw Failure.unavailable
                })
        }
    }

    public func close() {
        closed = true
        for guest in guests.values { guest.loaded.close() }
        guests.removeAll()
        identities.removeAll()
        active.removeAll()
    }

    private func link(to imports: inout Imports, store: Store, context: Context) {
        imports.define(module: "crabrix_proc_macro_v1", name: "exchange",
            Function(store: store, parameters: Array(repeating: .i32, count: 6), results: [.i32]) {
                [weak self] caller, arguments in
                guard let self, !self.closed else { throw Failure.unavailable }
                guard context.reply == nil else { throw Failure.unconsumedReply }
                guard let instance = caller.instance else { throw Failure.invalidRequest }
                let input = try self.read(instance, pointer: arguments[3].i32, count: arguments[4].i32)
                let reply = try self.exchange(context: context, caller: instance,
                    operation: arguments[0].i32, module: arguments[1].i32,
                    index: arguments[2].i32, flags: arguments[5].i32, input: input)
                guard reply.count <= self.maximumMessageBytes else { throw Failure.messageTooLarge }
                context.reply = reply
                return [.i32(UInt32(reply.count))]
            })
        imports.define(module: "crabrix_proc_macro_v1", name: "read_reply",
            Function(store: store, parameters: [.i32, .i32], results: [.i32]) {
                [weak self] caller, arguments in
                guard let self, !self.closed else { throw Failure.unavailable }
                guard let instance = caller.instance, let bytes = context.reply,
                      bytes.count == Int(arguments[1].i32) else { throw Failure.invalidRequest }
                try self.write(instance, pointer: arguments[0].i32, bytes: bytes)
                context.reply = nil
                return [.i32(UInt32(bytes.count))]
            })
    }

    private func exchange(context: Context, caller: Instance, operation: UInt32,
                          module: UInt32, index: UInt32, flags: UInt32,
                          input: [UInt8]) throws -> [UInt8] {
        switch operation {
        case 1:
            guard context.moduleID == 0, module == 0, index == 0, flags == 0 else {
                throw Failure.invalidRequest
            }
            var cursor = 0
            let path = try string(input, cursor: &cursor)
            let symbol = try string(input, cursor: &cursor)
            guard cursor == input.count, !path.isEmpty, !symbol.isEmpty else { throw Failure.invalidRequest }
            let identity = path + "\0" + symbol
            let id: UInt32
            let guest: Guest
            if let existing = identities[identity], let cached = guests[existing] {
                id = existing; guest = cached
            } else {
                guard guests.count + transientStores < maximumModules else { throw Failure.moduleLimit }
                id = UInt32(guests.count + 1)
                guest = try makeGuest(path: path, symbol: symbol, id: id, parent: caller.store)
                guests[id] = guest
                identities[identity] = id
            }
            let declarations = try withBudget(from: caller.store, to: guest.instance.store) {
                try takeReply(guest.instance, function: "__crabrix_pm_metadata", arguments: [.i32(guest.declarations)])
            }
            return littleEndian(1) + littleEndian(id) + declarations
        case 2:
            guard context.moduleID == 0, flags <= 1, let cached = guests[module] else {
                throw Failure.invalidRequest
            }
            guard active.count < maximumDepth else { throw Failure.depthLimit }
            // A recursive expansion must not overwrite an already active
            // proc_macro client's TLS or invalidate its symbol interner.
            let recursive = active.contains { $0.moduleID == module }
            let guest: Guest
            if recursive {
                guard guests.count + transientStores < maximumModules else { throw Failure.moduleLimit }
                transientStores += 1
                do { guest = try makeGuest(path: cached.path, symbol: cached.symbol, id: module, parent: caller.store) }
                catch { transientStores -= 1; throw error }
            } else { guest = cached }
            defer {
                if recursive { guest.loaded.close(); transientStores -= 1 }
            }
            active.append(ActiveCall(moduleID: module, parent: caller))
            defer { active.removeLast() }
            return try withBudget(from: caller.store, to: guest.instance.store) {
                let pointer = try putInput(input, in: guest.instance)
                return try takeReply(guest.instance, function: "__crabrix_pm_expand",
                    arguments: [.i32(guest.declarations), .i32(index), .i32(pointer),
                                .i32(UInt32(input.count)), .i32(flags)])
            }
        case 3:
            guard context.moduleID != 0, module == 0, index == 0, flags == 0,
                  let frame = active.last, frame.moduleID == context.moduleID else {
                throw Failure.inactiveDispatcher
            }
            return try withBudget(from: caller.store, to: frame.parent.store) {
                let pointer = try putInput(input, in: frame.parent)
                return try takeReply(frame.parent, function: "__crabrix_pm_dispatch",
                    arguments: [.i32(pointer), .i32(UInt32(input.count))])
            }
        default: throw Failure.invalidRequest
        }
    }

    private func makeGuest(path: String, symbol: String, id: UInt32, parent: Store) throws -> Guest {
        let store = Store(engine: engine)
        store.resourceLimiter = MacroLimiter(memoryLimit: memoryPerModule)
        var imports = Imports()
        link(to: &imports, store: store, context: Context(moduleID: id))
        let loaded = try withBudget(from: parent, to: store) {
            try loader(path, symbol, store, &imports)
        }
        do {
            guard loaded.instance.store === store else { throw Failure.invalidRequest }
            for name in ["__crabrix_pm_alloc", "__crabrix_pm_free", "__crabrix_pm_metadata", "__crabrix_pm_expand"] {
                guard loaded.instance.exports[function: name] != nil else { throw Failure.missingExport(name) }
            }
            guard let address = loaded.instance.exports[global: symbol], case .i32(let pointer) = address.value else {
                throw Failure.missingExport(symbol)
            }
            return Guest(loaded: loaded, path: path, symbol: symbol, declarations: pointer)
        } catch { loaded.close(); throw error }
    }

    // These stores execute synchronously on one compiler queue. Copying the
    // remaining fuel before and after every transition charges nested RPC too;
    // a macro cannot receive a fresh budget on each callback or expansion.
    private func withBudget<T>(from source: Store, to destination: Store,
                               body: () throws -> T) rethrows -> T {
        destination.fuel = source.fuel
        destination.cancellationProbe = source.cancellationProbe
        defer { source.fuel = destination.fuel }
        return try body()
    }

    private func putInput(_ bytes: [UInt8], in instance: Instance) throws -> UInt32 {
        let result = try invoke(instance, "__crabrix_pm_alloc", [.i32(UInt32(bytes.count))])
        guard case .i32(let pointer) = result else { throw Failure.invalidRequest }
        try write(instance, pointer: pointer, bytes: bytes)
        return pointer
    }

    private func takeReply(_ instance: Instance, function: String, arguments: [Value]) throws -> [UInt8] {
        let result = try invoke(instance, function, arguments)
        guard case .i64(let packed) = result else { throw Failure.invalidRequest }
        let pointer = UInt32(truncatingIfNeeded: packed), length = UInt32(packed >> 32)
        let bytes = try read(instance, pointer: pointer, count: length)
        guard let free = instance.exports[function: "__crabrix_pm_free"] else {
            throw Failure.missingExport("__crabrix_pm_free")
        }
        _ = try free([.i32(pointer), .i32(length)])
        return bytes
    }

    private func invoke(_ instance: Instance, _ name: String, _ arguments: [Value]) throws -> Value {
        guard let function = instance.exports[function: name] else { throw Failure.missingExport(name) }
        let results = try function(arguments)
        guard results.count == 1 else { throw Failure.invalidRequest }
        return results[0]
    }

    private func read(_ instance: Instance, pointer: UInt32, count: UInt32) throws -> [UInt8] {
        guard count <= maximumMessageBytes else { throw Failure.messageTooLarge }
        guard let memory = instance.exports[memory: "memory"] else { throw Failure.missingExport("memory") }
        let start = Int(pointer), length = Int(count)
        guard start <= memory.byteCount, length <= memory.byteCount - start else { throw Failure.invalidRequest }
        return memory.withUnsafeBufferPointer(offset: UInt(start), count: length) { Array($0) }
    }

    private func write(_ instance: Instance, pointer: UInt32, bytes: [UInt8]) throws {
        guard bytes.count <= maximumMessageBytes else { throw Failure.messageTooLarge }
        guard let memory = instance.exports[memory: "memory"] else { throw Failure.missingExport("memory") }
        let start = Int(pointer)
        guard start <= memory.byteCount, bytes.count <= memory.byteCount - start else { throw Failure.invalidRequest }
        memory.withUnsafeMutableBufferPointer(offset: UInt(start), count: bytes.count) { buffer in
            for index in bytes.indices { buffer[index] = bytes[index] }
        }
    }

    private func littleEndian(_ word: UInt32) -> [UInt8] {
        (0..<4).map { UInt8(truncatingIfNeeded: word >> ($0 * 8)) }
    }

    private func string(_ bytes: [UInt8], cursor: inout Int) throws -> String {
        guard bytes.count - cursor >= 4 else { throw Failure.invalidRequest }
        let length = (0..<4).reduce(UInt32(0)) { $0 | UInt32(bytes[cursor + $1]) << ($1 * 8) }
        cursor += 4
        guard length <= 16 * 1024, Int(length) <= bytes.count - cursor else { throw Failure.invalidRequest }
        let slice = bytes[cursor..<(cursor + Int(length))]
        guard !slice.contains(0), let value = String(validating: slice, as: UTF8.self) else { throw Failure.invalidRequest }
        cursor += Int(length)
        return value
    }
}
