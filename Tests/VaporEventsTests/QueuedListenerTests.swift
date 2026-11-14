#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
import Vapor
import VaporEvents
import XCTQueues

private actor QueuedRecorder {
    private(set) var handled: [UUID] = []

    func record(_ id: UUID) {
        self.handled.append(id)
    }
}

private struct QueuedOrderShipped: Event {
    let orderID: UUID
}

private struct QueuedOrderListener: ShouldQueue {
    let recorder: QueuedRecorder

    func handle(_ event: QueuedOrderShipped) async throws {
        await self.recorder.record(event.orderID)
    }
}

@Suite("Queued listeners")
struct QueuedListenerTests {
    @Test
    func dispatchEnqueuesJob() async throws {
        // Create a testing application with the test queue.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        app.queues.use(.asyncTest)

        // Register a queued listener and dispatch.
        let recorder = QueuedRecorder()
        await app.events.listen(QueuedOrderListener(recorder: recorder))
        let id = UUID()
        try await app.events.dispatch(QueuedOrderShipped(orderID: id))

        // Verify the job was enqueued and the handler did not run.
        let payloads = app.queues.asyncTest.all(ListenerJob<QueuedOrderListener>.self)
        let handled = await recorder.handled
        #expect(payloads.map(\.orderID) == [id])
        #expect(handled.isEmpty)
    }

    @Test
    func dequeueRunsHandler() async throws {
        // Create a testing application with the test queue.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        app.queues.use(.asyncTest)

        // Register a queued listener and dispatch.
        let recorder = QueuedRecorder()
        let listener = QueuedOrderListener(recorder: recorder)
        await app.events.listen(listener)
        let id = UUID()
        try await app.events.dispatch(QueuedOrderShipped(orderID: id))

        // Dequeue the job and verify the handler ran.
        let payload = try #require(app.queues.asyncTest.first(ListenerJob<QueuedOrderListener>.self))
        try await ListenerJob(listener: listener).dequeue(app.queues.queue.context, payload)

        let handled = await recorder.handled
        #expect(handled == [id])
    }

    @Test
    func receiveSkipsQueuedListener() async throws {
        // Create a testing application with the test queue.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        app.queues.use(.asyncTest)

        // Register a queued listener and receive an event.
        let recorder = QueuedRecorder()
        await app.events.listen(QueuedOrderListener(recorder: recorder))
        try await app.events.receive(QueuedOrderShipped(orderID: UUID()))

        // Verify nothing was enqueued or handled.
        let payloads = app.queues.asyncTest.all(ListenerJob<QueuedOrderListener>.self)
        let handled = await recorder.handled
        #expect(payloads.isEmpty)
        #expect(handled.isEmpty)
    }

    @Test
    func duplicateQueuedListenerIsSkipped() async throws {
        // Create a testing application with the test queue.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        app.queues.use(.asyncTest)

        // Register the same queued listener type twice and dispatch.
        let recorder = QueuedRecorder()
        await app.events.listen(QueuedOrderListener(recorder: recorder))
        await app.events.listen(QueuedOrderListener(recorder: recorder))
        let id = UUID()
        try await app.events.dispatch(QueuedOrderShipped(orderID: id))

        // Verify only one job was enqueued.
        let payloads = app.queues.asyncTest.all(ListenerJob<QueuedOrderListener>.self)
        #expect(payloads.map(\.orderID) == [id])
    }
}
