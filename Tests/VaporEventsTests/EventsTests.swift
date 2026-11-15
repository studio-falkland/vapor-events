#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
import Vapor
import VaporEvents
import VaporTesting

private struct OrderShipped: Event {
    let orderID: UUID
}

private actor Recorder {
    private(set) var count = 0

    func record() {
        self.count += 1
    }
}

private struct RecordingListener: EventListener {
    let recorder: Recorder

    func handle(_ event: OrderShipped) async throws {
        await self.recorder.record()
    }
}

@Suite("Events")
struct EventsTests {
    @Test
    func returnsSameBus() async throws {
        try await withApp { app in
            // Create and register the events holder.
            let events = Events()
            app.addLifecycleHandler(events)

            // Verify the holder exposes one shared dispatcher.
            let first = try #require(events.bus as? EventDispatcher)
            let second = try #require(events.bus as? EventDispatcher)
            #expect(first === second)
        }
    }

    @Test
    func dispatchesThroughEvents() async throws {
        try await withApp { app in
            // Create and register the events holder.
            let events = Events()
            app.addLifecycleHandler(events)
            let recorder = Recorder()

            // Register a listener and dispatch through the bus.
            await events.bus.listen(RecordingListener(recorder: recorder))
            try await events.bus.dispatch(OrderShipped(orderID: UUID()))

            // Verify the listener ran.
            let count = await recorder.count
            #expect(count == 1)
        }
    }
}
