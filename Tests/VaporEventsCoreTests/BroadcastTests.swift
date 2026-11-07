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
        // Create a shared broadcaster and two dispatchers.
        let broadcaster = InProcessBroadcaster()
        let origin = EventDispatcher(broadcaster: broadcaster, instanceID: "origin")
        let remote = EventDispatcher(broadcaster: broadcaster, instanceID: "remote")
        await origin.start()
        await remote.start()

        // Register a counting listener on the remote dispatcher.
        let counter = BroadcastCounter()
        await remote.listen(BroadcastCountingListener(counter: counter))

        // Dispatch a broadcast event from the origin.
        try await origin.dispatch(BroadcastEvent(id: UUID()))

        // Wait for the remote listener.
        await waitUntil { await counter.count == 1 }

        let count = await counter.count
        #expect(count == 1)

        await origin.shutdown()
        await remote.shutdown()
    }

    @Test
    func originDoesNotReceiveItsOwnBroadcast() async throws {
        // Create a broadcaster and a dispatcher.
        let broadcaster = InProcessBroadcaster()
        let origin = EventDispatcher(broadcaster: broadcaster, instanceID: "origin")
        await origin.start()

        // Register a counting listener.
        let counter = BroadcastCounter()
        await origin.listen(BroadcastCountingListener(counter: counter))

        // Dispatch a broadcast event.
        try await origin.dispatch(BroadcastEvent(id: UUID()))

        // Give the subscription a moment to process the echo.
        try await Task.sleep(for: .milliseconds(50))

        // Verify the listener ran once.
        let count = await counter.count
        #expect(count == 1)

        await origin.shutdown()
    }

    @Test
    func nonBroadcastEventIsNotPublished() async throws {
        // Create a shared broadcaster and two dispatchers.
        let broadcaster = InProcessBroadcaster()
        let origin = EventDispatcher(broadcaster: broadcaster, instanceID: "origin")
        let remote = EventDispatcher(broadcaster: broadcaster, instanceID: "remote")
        await origin.start()
        await remote.start()

        // Register a listener on the remote dispatcher.
        let counter = BroadcastCounter()
        await remote.listen(LocalCountingListener(counter: counter))

        // Dispatch a local event from the origin.
        try await origin.dispatch(LocalEvent(id: UUID()))

        // Give the subscription a moment to process.
        try await Task.sleep(for: .milliseconds(50))

        // Verify the remote listener did not run.
        let count = await counter.count
        #expect(count == 0)

        await origin.shutdown()
        await remote.shutdown()
    }

    @Test
    func remoteStreamReceivesBroadcast() async throws {
        // Create a shared broadcaster and two dispatchers.
        let broadcaster = InProcessBroadcaster()
        let origin = EventDispatcher(broadcaster: broadcaster, instanceID: "origin")
        let remote = EventDispatcher(broadcaster: broadcaster, instanceID: "remote")
        await origin.start()
        await remote.start()

        // Create a stream on the remote dispatcher.
        let stream = await remote.stream(BroadcastEvent.self)

        // Dispatch a broadcast event from the origin.
        let id = UUID()
        try await origin.dispatch(BroadcastEvent(id: id))

        // Read the event from the remote stream.
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event?.id == id)

        await origin.shutdown()
        await remote.shutdown()
    }

    @Test
    func shutdownStopsReceiving() async throws {
        // Create a shared broadcaster and two dispatchers.
        let broadcaster = InProcessBroadcaster()
        let origin = EventDispatcher(broadcaster: broadcaster, instanceID: "origin")
        let remote = EventDispatcher(broadcaster: broadcaster, instanceID: "remote")
        await origin.start()
        await remote.start()

        // Register a listener on the remote dispatcher.
        let counter = BroadcastCounter()
        await remote.listen(BroadcastCountingListener(counter: counter))

        // Shut down the remote dispatcher and dispatch.
        await remote.shutdown()
        try await origin.dispatch(BroadcastEvent(id: UUID()))

        // Give the subscription a moment to process.
        try await Task.sleep(for: .milliseconds(50))

        // Verify the remote listener did not run.
        let count = await counter.count
        #expect(count == 0)

        await origin.shutdown()
    }
}
