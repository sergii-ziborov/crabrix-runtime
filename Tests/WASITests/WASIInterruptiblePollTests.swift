import Testing
import WasmTypes
@_spi(WASIPlatform) @testable import WASI

@Suite struct WASIInterruptiblePollTests {
    enum Stop: Error { case requested }

    @Test func longHostWaitStopsBeforeItsTimerExpires() throws {
        let clock = SystemMonotonicClock()
        let started = try clock.now()
        let memory = WASIBoundedMemoryTests.Memory()
        let subscription = WASIAbi.Subscription(userData: 7,
            union: .clock(.init(id: .MONOTONIC, timeout: 60_000_000_000, precision: 0, flags: [])))
        #expect(throws: Stop.self) {
            try poll(subscriptions: [subscription],
                events: .init(baseAddress: .init(offset: 0), count: 1), FdTable(), memory: memory,
                cancellationCheck: {
                    if try clock.now() - started >= 25_000_000 { throw Stop.requested }
                })
        }
        #expect(try clock.now() - started < 500_000_000)
    }

    @Test func slicingDoesNotReportAnEarlyTimerEvent() throws {
        let clock = SystemMonotonicClock()
        let started = try clock.now()
        let memory = WASIBoundedMemoryTests.Memory()
        let subscription = WASIAbi.Subscription(userData: 7,
            union: .clock(.init(id: .MONOTONIC, timeout: 60_000_000, precision: 0, flags: [])))
        let count = try poll(subscriptions: [subscription],
            events: .init(baseAddress: .init(offset: 0), count: 1), FdTable(), memory: memory,
            cancellationCheck: {})
        #expect(count == 1)
        #expect(try clock.now() - started >= 58_000_000)
        let event = UnsafeGuestPointer<WASIAbi.Event>(offset: 0).read(from: memory)
        #expect(event.userData == 7)
        #expect(event.eventType == .clock)
    }
}
