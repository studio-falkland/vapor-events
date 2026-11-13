#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import VaporEventsCore

struct BroadcastEvent: ShouldBroadcast {
    let id: UUID
}

struct LocalEvent: Event {
    let id: UUID
}

private actor BroadcastCounter {
    private(set) var count = 0

    func increment() {
        self.count += 1
    }
}

private struct BroadcastCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: BroadcastEvent) async throws {
        await self.counter.increment()
    }
}

private struct ThrowingBroadcastListener: EventListener {
    func handle(_ event: BroadcastEvent) async throws {
        throw TestError.failed
    }
}

private struct LocalCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: LocalEvent) async throws {
        await self.counter.increment()
    }
}

private let postgresConnection = BroadcastConnection(rawValue: "postgres")

struct PostgresEvent: ShouldBroadcast {
    static var broadcastConnection: BroadcastConnection? { postgresConnection }
    let id: UUID
}

struct InProcessEvent: ShouldBroadcast {
    static var broadcastConnection: BroadcastConnection? { .inProcess }
    let id: UUID
}

private struct PostgresCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: PostgresEvent) async throws {
        await self.counter.increment()
    }
}

private struct InProcessCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: InProcessEvent) async throws {
        await self.counter.increment()
    }
}

private actor SpyDriver: BroadcastDriver {
    private let inner = InProcessBroadcastDriver()
    private(set) var publishCount = 0
    private(set) var subscribeCount = 0

    func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws {
        self.publishCount += 1
        try await self.inner.publish(envelope)
    }

    func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E> {
        self.subscribeCount += 1
        return await self.inner.subscribe(to: type)
    }

    func shutdown() async {
        await self.inner.shutdown()
    }
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
    func remoteDispatcherReceivesBroadcast() async throws {
        // Create a shared driver and two dispatchers.
        let broadcaster = Broadcaster()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(broadcaster: broadcaster, dispatcher: remoteDispatcher, instanceID: "remote")
        origin.start()
        remote.start()

        // Register a counting listener on the remote dispatcher.
        let counter = BroadcastCounter()
        await remoteDispatcher.listen(BroadcastCountingListener(counter: counter))

        // Dispatch a broadcast event from the origin.
        try await originDispatcher.dispatch(BroadcastEvent(id: UUID()))

        // Wait for the remote listener.
        await waitUntil { await counter.count == 1 }

        let count = await counter.count
        #expect(count == 1)

        origin.shutdown()
        remote.shutdown()
    }

    @Test
    func broadcastStillPublishedWhenListenerThrows() async throws {
        // Create a shared driver and two dispatchers.
        let broadcaster = Broadcaster()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(broadcaster: broadcaster, dispatcher: remoteDispatcher, instanceID: "remote")
        origin.start()
        remote.start()

        // Register a throwing listener on the origin and a counter on the remote.
        await originDispatcher.listen(ThrowingBroadcastListener())
        let counter = BroadcastCounter()
        await remoteDispatcher.listen(BroadcastCountingListener(counter: counter))

        // Dispatch, expect the error, and verify the broadcast still arrived.
        await #expect(throws: TestError.self) {
            try await originDispatcher.dispatch(BroadcastEvent(id: UUID()))
        }
        await waitUntil { await counter.count == 1 }
        #expect(await counter.count == 1)

        origin.shutdown()
        remote.shutdown()
    }

    @Test
    func originDoesNotReceiveItsOwnBroadcast() async throws {
        // Create a driver and a dispatcher.
        let broadcaster = Broadcaster()
        let dispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: dispatcher, instanceID: "origin")
        origin.start()

        // Register a counting listener.
        let counter = BroadcastCounter()
        await dispatcher.listen(BroadcastCountingListener(counter: counter))

        // Dispatch a broadcast event.
        try await dispatcher.dispatch(BroadcastEvent(id: UUID()))

        // Give the subscription a moment to process the echo.
        try await Task.sleep(for: .milliseconds(50))

        // Verify the listener ran once.
        let count = await counter.count
        #expect(count == 1)

        origin.shutdown()
    }

    @Test
    func nonBroadcastEventIsNotPublished() async throws {
        // Create a shared driver and two dispatchers.
        let broadcaster = Broadcaster()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(broadcaster: broadcaster, dispatcher: remoteDispatcher, instanceID: "remote")
        origin.start()
        remote.start()

        // Register a listener on the remote dispatcher.
        let counter = BroadcastCounter()
        await remoteDispatcher.listen(LocalCountingListener(counter: counter))

        // Dispatch a local event from the origin.
        try await originDispatcher.dispatch(LocalEvent(id: UUID()))

        // Give the subscription a moment to process.
        try await Task.sleep(for: .milliseconds(50))

        // Verify the remote listener did not run.
        let count = await counter.count
        #expect(count == 0)

        origin.shutdown()
        remote.shutdown()
    }

    @Test
    func remoteStreamReceivesBroadcast() async throws {
        // Create a shared driver and two dispatchers.
        let broadcaster = Broadcaster()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(broadcaster: broadcaster, dispatcher: remoteDispatcher, instanceID: "remote")
        origin.start()
        remote.start()

        // Create a stream on the remote dispatcher.
        let stream = await remoteDispatcher.stream(BroadcastEvent.self)

        // Dispatch a broadcast event from the origin.
        let id = UUID()
        try await originDispatcher.dispatch(BroadcastEvent(id: id))

        // Read the event from the remote stream.
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event?.id == id)

        origin.shutdown()
        remote.shutdown()
    }

    @Test
    func shutdownStopsReceiving() async throws {
        // Create a shared driver and two dispatchers.
        let broadcaster = Broadcaster()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(broadcaster: broadcaster, dispatcher: remoteDispatcher, instanceID: "remote")
        origin.start()
        remote.start()

        // Register a listener on the remote dispatcher.
        let counter = BroadcastCounter()
        await remoteDispatcher.listen(BroadcastCountingListener(counter: counter))

        // Shut down the remote system and dispatch.
        remote.shutdown()
        try await originDispatcher.dispatch(BroadcastEvent(id: UUID()))

        // Give the subscription a moment to process.
        try await Task.sleep(for: .milliseconds(50))

        // Verify the remote listener did not run.
        let count = await counter.count
        #expect(count == 0)

        origin.shutdown()
    }

    @Test
    func inProcessIsRegisteredByDefault() async throws {
        // Create a broadcaster and two relays.
        let broadcaster = Broadcaster()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(broadcaster: broadcaster, dispatcher: remoteDispatcher, instanceID: "remote")
        origin.start()
        remote.start()

        // Register a listener for an event that explicitly uses in-process.
        let counter = BroadcastCounter()
        await remoteDispatcher.listen(InProcessCountingListener(counter: counter))

        // Dispatch the event.
        try await originDispatcher.dispatch(InProcessEvent(id: UUID()))

        // Wait for the remote listener.
        await waitUntil { await counter.count == 1 }
        #expect(await counter.count == 1)

        origin.shutdown()
        remote.shutdown()
    }

    @Test
    func eventConnectionSelectsRegisteredDriver() async throws {
        // Create a broadcaster with a spy registered for the postgres connection.
        let broadcaster = Broadcaster()
        let spy = SpyDriver()
        broadcaster.register(postgresConnection, spy)

        // Create two relays sharing the broadcaster.
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(broadcaster: broadcaster, dispatcher: remoteDispatcher, instanceID: "remote")
        origin.start()
        remote.start()

        // Register a listener on the remote dispatcher.
        let counter = BroadcastCounter()
        await remoteDispatcher.listen(PostgresCountingListener(counter: counter))

        // Dispatch a postgres event from the origin.
        try await originDispatcher.dispatch(PostgresEvent(id: UUID()))

        // Wait for the remote listener.
        await waitUntil { await counter.count == 1 }

        // Verify the spy handled the subscription and publication.
        #expect(await counter.count == 1)
        #expect(await spy.subscribeCount == 1)
        #expect(await spy.publishCount == 1)

        origin.shutdown()
        remote.shutdown()
    }

    @Test
    func useDefaultChangesFallback() async throws {
        // Create a broadcaster with a spy as the default.
        let broadcaster = Broadcaster()
        let spy = SpyDriver()
        broadcaster.register(postgresConnection, spy)
        broadcaster.useDefault(postgresConnection)

        // Create two relays sharing the broadcaster.
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(broadcaster: broadcaster, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(broadcaster: broadcaster, dispatcher: remoteDispatcher, instanceID: "remote")
        origin.start()
        remote.start()

        // Register a listener for an event with no explicit connection.
        let counter = BroadcastCounter()
        await remoteDispatcher.listen(BroadcastCountingListener(counter: counter))

        // Dispatch the event.
        try await originDispatcher.dispatch(BroadcastEvent(id: UUID()))

        // Wait for the remote listener.
        await waitUntil { await counter.count == 1 }

        // Verify the spy handled the subscription and publication.
        #expect(await counter.count == 1)
        #expect(await spy.subscribeCount == 1)
        #expect(await spy.publishCount == 1)

        origin.shutdown()
        remote.shutdown()
    }
}
