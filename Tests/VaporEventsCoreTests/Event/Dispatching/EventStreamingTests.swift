#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import VaporEventsCore

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

private func nextWithTimeout<E: Event>(
    _ stream: AsyncStream<E>,
    timeout: Duration = .milliseconds(100)
) async -> E? {
    // Race the next element against a timeout.
    await withTaskGroup(of: E?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            return await iterator.next()
        }
        group.addTask {
            try? await Task.sleep(for: timeout)
            return nil
        }
        let result = await group.next() ?? nil
        group.cancelAll()
        return result
    }
}

@Suite("Event streaming")
struct EventStreamingTests {
    @Test
    func streamReceivesEvents() async throws {
        // Create a dispatcher and a stream.
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.stream(OrderShipped.self)

        // Register the consumer before dispatching.
        var iterator = stream.makeAsyncIterator()

        // Dispatch an event.
        let id = UUID()
        try await dispatcher.dispatch(OrderShipped(orderID: id))

        // Read the event from the stream.
        let event = await iterator.next()
        #expect(event?.orderID == id)
    }

    @Test
    func multipleStreamsReceiveEvents() async throws {
        // Create a dispatcher and two subscriber streams.
        let dispatcher = EventDispatcher()
        let firstStream = await dispatcher.stream(OrderShipped.self)
        let secondStream = await dispatcher.stream(OrderShipped.self)

        // Register two consumers before dispatching.
        var firstIterator = firstStream.makeAsyncIterator()
        var secondIterator = secondStream.makeAsyncIterator()

        // Dispatch an event.
        let id = UUID()
        try await dispatcher.dispatch(OrderShipped(orderID: id))

        // Verify both consumers received it.
        let firstEvent = await firstIterator.next()
        let secondEvent = await secondIterator.next()
        #expect(firstEvent?.orderID == id)
        #expect(secondEvent?.orderID == id)
    }

    @Test
    func streamsAreFedAfterListeners() async throws {
        // Create a dispatcher, a recorder, and a stream.
        let dispatcher = EventDispatcher()
        let recorder = SequenceRecorder()
        let stream = await dispatcher.stream(OrderShipped.self)

        // Start a consumer and wait until it is registered.
        let ready = AsyncStream<Void>.makeStream()
        let consumer = Task {
            var iterator = stream.makeAsyncIterator()
            ready.continuation.yield()
            while let _ = await iterator.next() {
                await recorder.record("stream")
            }
        }
        for await _ in ready.stream { break }

        // Register a listener that records its run.
        await dispatcher.listen(LowPriorityListener { _ in await recorder.record("listener") })

        // Dispatch and wait for the consumer to record.
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))
        await waitUntil { await recorder.values.contains("stream") }
        consumer.cancel()
        await consumer.value

        // Verify the listener ran before the stream was fed.
        let values = await recorder.values
        #expect(values == ["listener", "stream"])
    }

    @Test
    func streamsAreFedWhenListenerThrows() async throws {
        // Create a dispatcher and a stream.
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.stream(OrderShipped.self)

        // Register a throwing listener.
        await dispatcher.listen(ThrowingListener())

        // Dispatch and expect the error.
        let id = UUID()
        await #expect(throws: TestError.self) {
            try await dispatcher.dispatch(OrderShipped(orderID: id))
        }

        // Verify the stream received the event before the error was rethrown.
        let event = await nextWithTimeout(stream)
        #expect(event?.orderID == id)
    }

    @Test
    func receiveFeedsStreamsWhenListenerThrows() async throws {
        // Create a dispatcher and a stream.
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.stream(OrderShipped.self)

        // Register a throwing listener.
        await dispatcher.listen(ThrowingListener())

        // Receive and expect the error.
        let id = UUID()
        await #expect(throws: TestError.self) {
            try await dispatcher.receive(OrderShipped(orderID: id))
        }

        // Verify the stream received the event before the error was rethrown.
        let event = await nextWithTimeout(stream)
        #expect(event?.orderID == id)
    }
}
