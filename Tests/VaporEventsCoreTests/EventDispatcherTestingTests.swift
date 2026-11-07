#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import VaporEventsCore

struct OtherEvent: Event {
    let id: UUID

    init(id: UUID = UUID()) {
        self.id = id
    }
}

@Suite("FakeEventDispatcher")
struct FakeEventDispatcherTests {
    @Test
    func recordsDispatches() async throws {
        // Create a fake dispatcher.
        let dispatcher = FakeEventDispatcher()

        // Dispatch an event.
        let id = UUID()
        try await dispatcher.dispatch(OrderShipped(orderID: id))

        // Verify the event was recorded.
        let events = await dispatcher.dispatched(OrderShipped.self)
        #expect(events.map(\.orderID) == [id])
    }

    @Test
    func dispatchedFiltersByType() async throws {
        // Create a fake dispatcher.
        let dispatcher = FakeEventDispatcher()

        // Dispatch two event types.
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))
        try await dispatcher.dispatch(OtherEvent())

        // Verify filtering by type.
        let shipped = await dispatcher.dispatched(OrderShipped.self)
        let other = await dispatcher.dispatched(OtherEvent.self)
        #expect(shipped.count == 1)
        #expect(other.count == 1)
    }

    @Test
    func assertDispatchedPassesAndFails() async throws {
        // Create a fake dispatcher and dispatch an event.
        let dispatcher = FakeEventDispatcher()
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))

        // Verify the assertion passes.
        try await dispatcher.assertDispatched(OrderShipped.self)

        // Verify the assertion fails for an undispatched type.
        await #expect(throws: EventAssertionError.self) {
            try await dispatcher.assertDispatched(OtherEvent.self)
        }
    }

    @Test
    func assertNotDispatchedPassesAndFails() async throws {
        // Create a fake dispatcher and dispatch an event.
        let dispatcher = FakeEventDispatcher()
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))

        // Verify the assertion passes for an undispatched type.
        try await dispatcher.assertNotDispatched(OtherEvent.self)

        // Verify the assertion fails for a dispatched type.
        await #expect(throws: EventAssertionError.self) {
            try await dispatcher.assertNotDispatched(OrderShipped.self)
        }
    }

    @Test
    func assertListeningPassesAndFails() async throws {
        // Create a fake dispatcher and register a listener.
        let dispatcher = FakeEventDispatcher()
        await dispatcher.listen(RecordingListener(recorder: Recorder()))

        // Verify the assertion passes.
        try await dispatcher.assertListening(RecordingListener.self)

        // Verify the assertion fails for an unregistered listener.
        await #expect(throws: EventAssertionError.self) {
            try await dispatcher.assertListening(ThrowingListener.self)
        }
    }

    @Test
    func resetClearsRecordedEvents() async throws {
        // Create a fake dispatcher and dispatch an event.
        let dispatcher = FakeEventDispatcher()
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))

        // Reset and verify nothing is recorded.
        await dispatcher.reset()
        let events = await dispatcher.dispatched(OrderShipped.self)
        #expect(events.isEmpty)
    }
}
