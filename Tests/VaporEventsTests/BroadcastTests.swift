#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
import Vapor
import VaporEvents
import VaporTesting

private let sharedConnection = BroadcastConnection(rawValue: "shared")

private struct SharedEvent: ShouldBroadcast {
    static var broadcastConnection: BroadcastConnection? { sharedConnection }
    let id: UUID
}

private struct LocalBroadcastEvent: ShouldBroadcast {
    let id: UUID
}

private actor BroadcastCounter {
    private(set) var count = 0

    func increment() {
        self.count += 1
    }
}

private struct SharedCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: SharedEvent) async throws {
        await self.counter.increment()
    }
}

private struct LocalCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: LocalBroadcastEvent) async throws {
        await self.counter.increment()
    }
}

/// A driver that records the event names it publishes.
private actor RecordingDriver: BroadcastDriver {
    private(set) var published: [String] = []

    func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws {
        self.published.append(E.name)
    }

    func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E> {
        // Hand out a finished stream; this driver only records publishes.
        let (stream, continuation) = AsyncStream<EventEnvelope<E>>.makeStream()
        continuation.finish()
        return EventSubscription(stream: stream, cancel: {})
    }

    func shutdown() async {}
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    _ condition: @Sendable () async -> Bool
) async {
    // Poll until the condition holds or the deadline passes.
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("Broadcast")
struct BroadcastTests {
    @Test
    func defaultsToInProcess() async throws {
        try await withApp { app in
            // Create and register the events holder.
            let events = Events()
            app.addLifecycleHandler(events)

            // Register a listener and dispatch a broadcast event.
            let counter = BroadcastCounter()
            await events.bus.listen(LocalCountingListener(counter: counter))
            try await events.bus.dispatch(LocalBroadcastEvent(id: UUID()))

            // Give the relay a moment to process its own echo.
            try await Task.sleep(for: .milliseconds(50))

            // Verify the listener ran once.
            #expect(await counter.count == 1)
        }
    }

    @Test
    func registeredConnectionBroadcastsBetweenHolders() async throws {
        try await withApp { app in
            // Create two holders sharing a driver.
            let driver = InProcessBroadcastDriver()
            let events1 = Events()
            let events2 = Events()
            app.addLifecycleHandler(events1)
            app.addLifecycleHandler(events2)

            // Register the shared connection on both holders.
            events1.broadcast.register(sharedConnection, driver)
            events2.broadcast.register(sharedConnection, driver)

            // Register a listener on the second holder.
            let counter = BroadcastCounter()
            await events2.bus.listen(SharedCountingListener(counter: counter))

            // Dispatch from the first holder.
            try await events1.bus.dispatch(SharedEvent(id: UUID()))

            // Wait for the second holder's listener.
            await waitUntil { await counter.count == 1 }
            #expect(await counter.count == 1)
        }
    }

    @Test
    func useDefaultRoutesToRegisteredDriver() async throws {
        try await withApp { app in
            // Create and register the events holder.
            let events = Events()
            app.addLifecycleHandler(events)

            // Register a driver and make its connection the default.
            let driver = RecordingDriver()
            let connection = BroadcastConnection(rawValue: "test")
            events.broadcast
                .register(connection, driver)
                .useDefault(connection)

            // Dispatch a broadcast event and wait for the relay to publish it.
            try await events.bus.dispatch(LocalBroadcastEvent(id: UUID()))
            await waitUntil { await driver.published.contains(LocalBroadcastEvent.name) }
            #expect(await driver.published.contains(LocalBroadcastEvent.name))
        }
    }
}
