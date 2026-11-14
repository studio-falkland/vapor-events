#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
import Vapor
import VaporEvents

private struct OrderShipped: Event {
    let orderID: UUID
}

private actor Recorder {
    private(set) var count = 0

    func record() {
        self.count += 1
    }
}

private struct RecordingListener: EventListener {
    let recorder: Recorder

    func handle(_ event: OrderShipped) async throws {
        await self.recorder.record()
    }
}

@Suite("Application.events")
struct ApplicationEventsTests {
    @Test
    func returnsSameDispatcher() async throws {
        // Create a testing application.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }

        // Verify the accessor returns one shared dispatcher.
        let first = try #require(app.events as? EventDispatcher)
        let second = try #require(app.events as? EventDispatcher)
        #expect(first === second)
    }

    @Test
    func dispatchesThroughApplication() async throws {
        // Create a testing application and recorder.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }
        let recorder = Recorder()

        // Register a listener and dispatch through the application.
        await app.events.listen(RecordingListener(recorder: recorder))
        try await app.events.dispatch(OrderShipped(orderID: UUID()))

        // Verify the listener ran.
        let count = await recorder.count
        #expect(count == 1)
    }
}
