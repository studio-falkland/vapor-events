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

private struct LocalCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: LocalEvent) async throws {
        await self.counter.increment()
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
        let driver = InProcessBroadcastDriver()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(driver: driver, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(driver: driver, dispatcher: remoteDispatcher, instanceID: "remote")
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
    func originDoesNotReceiveItsOwnBroadcast() async throws {
        // Create a driver and a dispatcher.
        let driver = InProcessBroadcastDriver()
        let dispatcher = EventDispatcher()
        let origin = BroadcastRelay(driver: driver, dispatcher: dispatcher, instanceID: "origin")
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
        let driver = InProcessBroadcastDriver()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(driver: driver, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(driver: driver, dispatcher: remoteDispatcher, instanceID: "remote")
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
        let driver = InProcessBroadcastDriver()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(driver: driver, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(driver: driver, dispatcher: remoteDispatcher, instanceID: "remote")
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
        let driver = InProcessBroadcastDriver()
        let originDispatcher = EventDispatcher()
        let remoteDispatcher = EventDispatcher()
        let origin = BroadcastRelay(driver: driver, dispatcher: originDispatcher, instanceID: "origin")
        let remote = BroadcastRelay(driver: driver, dispatcher: remoteDispatcher, instanceID: "remote")
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
}
