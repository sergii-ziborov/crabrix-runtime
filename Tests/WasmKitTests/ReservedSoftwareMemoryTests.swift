import Testing
import WAT

@_spi(Fuzzing) @testable import WasmKit

#if os(macOS) || os(Linux)

@Suite struct ReservedSoftwareMemoryTests {
    private static let page = MemoryEntity.pageSize

    @Test func growthKeepsBaseAndZeroFillsNewPages() throws {
        let engine = Engine(configuration: .init(
            threadingModel: .token,
            memoryBoundsChecking: .software,
            softwareMemoryReservationBytes: 4 * Self.page
        ))
        let store = Store(engine: engine)
        let memory = try Memory(store: store, type: MemoryType(min: 1, max: 8))
        let originalBase = memory.handle.withValue { entity -> UnsafeMutableRawPointer in
            let base = entity.baseAddress!
            base.assumingMemoryBound(to: UInt8.self)[0] = 0x5A
            return base
        }

        let firstGrow = try memory.handle.withValue { entity in
            try entity.grow(by: 2, resourceLimiter: store.resourceLimiter)
        }
        #expect(firstGrow == .i32(1))
        memory.handle.withValue { entity in
            #expect(entity.baseAddress == originalBase)
            #expect(entity.byteCount == 3 * Self.page)
            #expect(entity.data[0] == 0x5A)
            #expect(entity.data[Self.page] == 0)
            #expect(entity.data[3 * Self.page - 1] == 0)
        }
        // The reservation is only a hint. A grow past it uses the malloc
        // fallback and preserves all previously committed bytes.
        let fallbackGrow = try memory.handle.withValue { entity in
            try entity.grow(by: 2, resourceLimiter: store.resourceLimiter)
        }
        #expect(fallbackGrow == .i32(3))
        memory.handle.withValue { entity in
            #expect(entity.byteCount == 5 * Self.page)
            #expect(entity.baseAddress != originalBase)
            #expect(entity.data[0] == 0x5A)
            #expect(entity.data[4 * Self.page] == 0)
        }
    }

    @Test func softwareBoundUsesCommittedSize() throws {
        let module = try parseWasm(bytes: wat2wasm("""
            (module
              (memory 1 4)
              (func (export "read") (result i32) (i32.load (i32.const 65536)))
              (func (export "grow") (result i32) (memory.grow (i32.const 1))))
            """))
        let engine = Engine(configuration: .init(
            threadingModel: .token,
            memoryBoundsChecking: .software,
            softwareMemoryReservationBytes: 4 * Self.page
        ))
        let store = Store(engine: engine)
        let instance = try module.instantiate(store: store)
        let read = try #require(instance.exports[function: "read"])
        let grow = try #require(instance.exports[function: "grow"])
        #expect(throws: Trap.self) { try read() }
        #expect(try grow() == [.i32(1)])
        #expect(try read() == [.i32(0)])
    }

    @Test func directRequestStillTrapsUnderSoftwareBounds() throws {
        let module = try parseWasm(bytes: wat2wasm("""
            (module
              (memory 1)
              (func (export "read") (result i32) (i32.load (i32.const 65536))))
            """))
        let engine = Engine(configuration: .init(
            threadingModel: .direct,
            memoryBoundsChecking: .software,
            softwareMemoryReservationBytes: 4 * Self.page
        ))
        guard case .token = engine.configuration.threadingModel else {
            Issue.record("software bounds must select the token dispatcher")
            return
        }
        let store = Store(engine: engine)
        let instance = try module.instantiate(store: store)
        let read = try #require(instance.exports[function: "read"])
        #expect(throws: Trap.self) { try read() }
    }

    @Test func reservationDoesNotBypassResourceLimiter() throws {
        final class TwoPageLimiter: ResourceLimiter {
            func limitMemoryGrowth(to desired: Int) throws -> Bool {
                desired <= 2 * MemoryEntity.pageSize
            }
        }

        let engine = Engine(configuration: .init(
            threadingModel: .token,
            memoryBoundsChecking: .software,
            softwareMemoryReservationBytes: 4 * Self.page
        ))
        let store = Store(engine: engine)
        store.resourceLimiter = TwoPageLimiter()
        let memory = try Memory(store: store, type: MemoryType(min: 1, max: 8))
        let allowed = try memory.handle.withValue { entity in
            try entity.grow(by: 1, resourceLimiter: store.resourceLimiter)
        }
        let denied = try memory.handle.withValue { entity in
            try entity.grow(by: 1, resourceLimiter: store.resourceLimiter)
        }
        #expect(allowed == .i32(1))
        #expect(denied == .i32(UInt32.max))
        memory.handle.withValue { entity in
            #expect(entity.byteCount == 2 * Self.page)
        }
    }
}

#endif
