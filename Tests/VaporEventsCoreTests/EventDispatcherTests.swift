#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import VaporEventsCore

private struct OrderShipped: Event {
    let orderID: UUID
}

private actor Recorder {
    private(set) var orderIDs: [UUID] = []

    func record(_ event: OrderShipped) {
        self.orderIDs.append(event.orderID)
    }
}

private struct RecordingListener: EventListener {
    let recorder: Recorder

    func handle(_ event: OrderShipped) async throws {
        await self.recorder.record(event)
    }
}

private actor SequenceRecorder {
    private(set) var values: [String] = []

    func record(_ value: String) {
        self.values.append(value)
    }
}

private struct LowPriorityListener: EventListener {
    static let priority = 0

    let record: @Sendable (OrderShipped) async -> Void

    func handle(_ event: OrderShipped) async throws {
        await self.record(event)
    }
}

private struct HighPriorityListener: EventListener {
    static let priority = 10

    let record: @Sendable (OrderShipped) async -> Void

    func handle(_ event: OrderShipped) async throws {
        await self.record(event)
    }
}

private enum TestError: Error {
    case failed
}

private struct ThrowingListener: EventListener {
    func handle(_ event: OrderShipped) async throws {
        throw TestError.failed
    }
}

private actor Counter {
    private(set) var count = 0

    func increment() {
        self.count += 1
    }

    func reset() {
        self.count = 0
    }
}

private struct CountingListener: EventListener {
    let counter: Counter

    func handle(_ event: OrderShipped) async throws {
        await self.counter.increment()
    }
}

@Suite("EventDispatcher")
struct EventDispatcherTests {
    @Test
    func dispatchesToListener() async throws {
        // Create a dispatcher and a recorder.
        let dispatcher = EventDispatcher()
        let recorder = Recorder()

        // Register the typed listener.
        await dispatcher.listen(RecordingListener(recorder: recorder))

        // Dispatch an event and verify it arrived.
        let id = UUID()
        try await dispatcher.dispatch(OrderShipped(orderID: id))
        let orderIDs = await recorder.orderIDs
        #expect(orderIDs == [id])
    }

    @Test
    func dispatchesToClosureListener() async throws {
        // Create a dispatcher and a recorder.
        let dispatcher = EventDispatcher()
        let recorder = Recorder()

        // Register a closure listener.
        await dispatcher.listen(OrderShipped.self) { event in
            await recorder.record(event)
        }

        // Dispatch an event and verify it arrived.
        let id = UUID()
        try await dispatcher.dispatch(OrderShipped(orderID: id))
        let orderIDs = await recorder.orderIDs
        #expect(orderIDs == [id])
    }

    @Test
    func runsHigherPriorityFirst() async throws {
        // Create a dispatcher and a recorder.
        let dispatcher = EventDispatcher()
        let recorder = SequenceRecorder()

        // Register low and high priority listeners.
        await dispatcher.listen(LowPriorityListener { _ in await recorder.record("low") })
        await dispatcher.listen(HighPriorityListener { _ in await recorder.record("high") })

        // Dispatch and verify the high priority listener ran first.
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))
        let values = await recorder.values
        #expect(values == ["high", "low"])
    }

    @Test
    func stopsOnFirstError() async throws {
        // Create a dispatcher and a recorder.
        let dispatcher = EventDispatcher()
        let recorder = Recorder()

        // Register a throwing listener before a recording listener.
        await dispatcher.listen(ThrowingListener())
        await dispatcher.listen(RecordingListener(recorder: recorder))

        // Dispatch and expect the error.
        await #expect(throws: TestError.self) {
            try await dispatcher.dispatch(OrderShipped(orderID: UUID()))
        }

        // Verify the second listener did not run.
        let orderIDs = await recorder.orderIDs
        #expect(orderIDs.isEmpty)
    }

    @Test
    func noListenersIsNoOp() async throws {
        // Create a dispatcher with no listeners.
        let dispatcher = EventDispatcher()

        // Dispatch and verify it does not throw.
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))
    }

    @Test
    func defaultNameIsFullyQualified() {
        // Verify the default name includes the type name.
        #expect(OrderShipped.name.contains("OrderShipped"))
    }

    @Test
    func handlesConcurrentDispatch() async throws {
        // Create a dispatcher and a recorder.
        let dispatcher = EventDispatcher()
        let recorder = Recorder()
        await dispatcher.listen(RecordingListener(recorder: recorder))

        // Dispatch from many concurrent tasks.
        let count = 100
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<count {
                group.addTask {
                    try? await dispatcher.dispatch(OrderShipped(orderID: UUID()))
                }
            }
        }

        // Verify every dispatch reached the listener.
        let orderIDs = await recorder.orderIDs
        #expect(orderIDs.count == count)
    }

    @Test
    func handlesConcurrentRegistrationAndDispatch() async throws {
        // Create a dispatcher and a counter.
        let dispatcher = EventDispatcher()
        let counter = Counter()

        // Register and dispatch concurrently.
        let listenerCount = 20
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<listenerCount {
                group.addTask {
                    await dispatcher.listen(CountingListener(counter: counter))
                }
            }
            for _ in 0..<50 {
                group.addTask {
                    try? await dispatcher.dispatch(OrderShipped(orderID: UUID()))
                }
            }
        }

        // Reset and dispatch once more.
        await counter.reset()
        try await dispatcher.dispatch(OrderShipped(orderID: UUID()))

        // Verify every registered listener runs exactly once.
        let count = await counter.count
        #expect(count == listenerCount)
    }
}
