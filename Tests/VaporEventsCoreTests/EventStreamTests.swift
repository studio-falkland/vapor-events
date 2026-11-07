#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import VaporEventsCore

@Suite("EventStream")
struct EventStreamTests {
    @Test
    func streamReceivesEvents() async throws {
        // Create a dispatcher and a stream.
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.stream(OrderShipped.self)

        // Dispatch an event.
        let id = UUID()
        try await dispatcher.dispatch(OrderShipped(orderID: id))

        // Read the event from the stream.
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event?.orderID == id)
    }

    @Test
    func multipleStreamsReceiveEvents() async throws {
        // Create a dispatcher and two streams.
        let dispatcher = EventDispatcher()
        let first = await dispatcher.stream(OrderShipped.self)
        let second = await dispatcher.stream(OrderShipped.self)

        // Dispatch an event.
        let id = UUID()
        try await dispatcher.dispatch(OrderShipped(orderID: id))

        // Verify both streams received it.
        var firstIterator = first.makeAsyncIterator()
        var secondIterator = second.makeAsyncIterator()
        let firstEvent = await firstIterator.next()
        let secondEvent = await secondIterator.next()
        #expect(firstEvent?.orderID == id)
        #expect(secondEvent?.orderID == id)
    }

    @Test
    func cancelRemovesSubscriber() async throws {
        // Create a dispatcher and a stream.
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.stream(OrderShipped.self)

        // Cancel the stream and dispatch.
        stream.cancel()
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))

        // Verify the stream ended without an event.
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event == nil)
    }

    @Test
    func streamsAreFedAfterListeners() async throws {
        // Create a dispatcher, a recorder, and a stream.
        let dispatcher = EventDispatcher()
        let recorder = SequenceRecorder()
        let stream = await dispatcher.stream(OrderShipped.self)

        // Consume the stream concurrently.
        let consumer = Task {
            for await _ in stream {
                await recorder.record("stream")
            }
        }

        // Register a listener that records its run.
        await dispatcher.listen(LowPriorityListener { _ in await recorder.record("listener") })

        // Dispatch, then stop the stream and wait for the consumer.
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))
        stream.cancel()
        await consumer.value

        // Verify the listener ran before the stream was fed.
        let values = await recorder.values
        #expect(values == ["listener", "stream"])
    }

    @Test
    func streamsAreNotFedWhenListenerThrows() async throws {
        // Create a dispatcher and a stream.
        let dispatcher = EventDispatcher()
        let stream = await dispatcher.stream(OrderShipped.self)

        // Register a throwing listener.
        await dispatcher.listen(ThrowingListener())

        // Dispatch and expect the error.
        await #expect(throws: TestError.self) {
            try await dispatcher.dispatch(OrderShipped(orderID: UUID()))
        }

        // Verify the stream did not receive the event.
        stream.cancel()
        var iterator = stream.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event == nil)
    }
}
