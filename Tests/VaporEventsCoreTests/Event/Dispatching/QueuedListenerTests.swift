#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
@testable import VaporEventsCore

private actor QueuedRecorder {
    private(set) var enqueued: [UUID] = []
    private(set) var handled: [UUID] = []

    func recordEnqueued(_ id: UUID) {
        self.enqueued.append(id)
    }

    func recordHandled(_ id: UUID) {
        self.handled.append(id)
    }
}

private struct QueuedListener: ShouldQueue {
    let recorder: QueuedRecorder

    func handle(_ event: OrderShipped) async throws {
        await self.recorder.recordHandled(event.orderID)
    }
}

private struct TestEnqueuing: EventEnqueuing {
    let recorder: QueuedRecorder

    func register<L: EventListener>(_ listener: L) {}

    func enqueue<E: Event>(_ event: E) async throws {
        guard let event = event as? OrderShipped else { return }
        await self.recorder.recordEnqueued(event.orderID)
    }
}

@Suite("Queued listeners")
struct QueuedListenerTests {
    @Test
    func dispatchEnqueuesInsteadOfHandling() async throws {
        // Create a dispatcher with a test enqueuing.
        let recorder = QueuedRecorder()
        let dispatcher = EventDispatcher(enqueuing: TestEnqueuing(recorder: recorder))
        await dispatcher.listen(QueuedListener(recorder: recorder))

        // Dispatch and verify the listener was enqueued, not handled.
        let id = UUID()
        try await dispatcher.dispatch(OrderShipped(orderID: id))

        let enqueued = await recorder.enqueued
        let handled = await recorder.handled
        #expect(enqueued == [id])
        #expect(handled.isEmpty)
    }

    @Test
    func dispatchStillEnqueuesWhenListenerThrows() async throws {
        // Create a dispatcher with a test enqueuing.
        let recorder = QueuedRecorder()
        let dispatcher = EventDispatcher(enqueuing: TestEnqueuing(recorder: recorder))
        await dispatcher.listen(ThrowingListener())
        await dispatcher.listen(QueuedListener(recorder: recorder))

        // Dispatch, expect the error, and verify the listener was still enqueued.
        let id = UUID()
        await #expect(throws: TestError.self) {
            try await dispatcher.dispatch(OrderShipped(orderID: id))
        }

        let enqueued = await recorder.enqueued
        #expect(enqueued == [id])
    }

    @Test
    func receiveSkipsQueuedListeners() async throws {
        // Create a dispatcher with a test enqueuing.
        let recorder = QueuedRecorder()
        let dispatcher = EventDispatcher(enqueuing: TestEnqueuing(recorder: recorder))
        await dispatcher.listen(QueuedListener(recorder: recorder))

        // Receive and verify the listener was not enqueued.
        try await dispatcher.receive(OrderShipped(orderID: UUID()))

        let enqueued = await recorder.enqueued
        #expect(enqueued.isEmpty)
    }

    @Test
    func receiveRunsListeners() async throws {
        // Create a dispatcher with a test enqueuing.
        let recorder = QueuedRecorder()
        let dispatcher = EventDispatcher(enqueuing: TestEnqueuing(recorder: recorder))
        await dispatcher.listen(OrderShipped.self) { event in
            await recorder.recordHandled(event.orderID)
        }

        // Receive and verify the listener ran.
        let id = UUID()
        try await dispatcher.receive(OrderShipped(orderID: id))

        let handled = await recorder.handled
        #expect(handled == [id])
    }
}
