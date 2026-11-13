#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import PostgresNIO
import Testing
@testable import VaporEventsPostgres
import VaporEventsCore

struct BroadcastEvent: Event {
    let id: UUID
}

struct OtherBroadcastEvent: Event {
    let id: UUID
}

struct LargeBroadcastEvent: Event {
    let id: UUID
    let payload: String
}

@Suite("PostgresBroadcastDriver", .enabled(if: PostgresTestEnvironment.isConfigured))
struct PostgresBroadcastDriverTests {
    @Test
    func publishesAndReceivesMultipleEventTypes() async throws {
        // Create and run a client.
        let client = PostgresClient(
            configuration: PostgresTestEnvironment.configuration,
            backgroundLogger: Logger(label: "test")
        )
        let clientTask = Task { await client.run() }
        defer { clientTask.cancel() }

        // Create a broadcaster and subscribe to two event types.
        let broadcaster = PostgresBroadcastDriver(client: client)
        let firstSubscription = await broadcaster.subscribe(to: BroadcastEvent.self)
        let secondSubscription = await broadcaster.subscribe(to: OtherBroadcastEvent.self)

        // Let the listener finish issuing LISTEN before publishing.
        try await Task.sleep(for: .milliseconds(100))

        // Publish one envelope per event type.
        let first = BroadcastEvent(id: UUID())
        let second = OtherBroadcastEvent(id: UUID())
        try await broadcaster.publish(EventEnvelope(event: first, origin: "origin"))
        try await broadcaster.publish(EventEnvelope(event: second, origin: "origin"))

        // Read both envelopes with a timeout.
        let firstReceived = await next(firstSubscription)
        let secondReceived = await next(secondSubscription)
        #expect(firstReceived?.event.id == first.id)
        #expect(secondReceived?.event.id == second.id)

        // Clean up.
        firstSubscription.cancel()
        secondSubscription.cancel()
        await broadcaster.shutdown()
    }
}

@Suite("PostgresBroadcastDriver payloads")
struct PostgresBroadcastDriverPayloadTests {
    @Test
    func rejectsOversizedPayloads() async throws {
        // Create a client without running it; the size check happens first.
        let client = PostgresClient(
            configuration: PostgresTestEnvironment.configuration,
            backgroundLogger: Logger(label: "test")
        )
        let broadcaster = PostgresBroadcastDriver(client: client)

        // Create an event larger than the payload limit.
        let event = LargeBroadcastEvent(id: UUID(), payload: String(repeating: "x", count: 9_000))
        let envelope = EventEnvelope(event: event, origin: "origin")

        // Verify publication is rejected before it reaches the client.
        await #expect(throws: EventTransportError.self) {
            try await broadcaster.publish(envelope)
        }

        await broadcaster.shutdown()
    }
}

/// Reads the next envelope with a timeout.
private func next<E: Event>(
    _ subscription: EventSubscription<E>,
    timeout: Duration = .seconds(5)
) async -> EventEnvelope<E>? {
    await withTaskGroup(of: EventEnvelope<E>?.self) { group in
        group.addTask {
            var iterator = subscription.makeAsyncIterator()
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

private enum PostgresTestEnvironment {
    static var isConfigured: Bool {
        ProcessInfo.processInfo.environment["POSTGRES_HOST"] != nil
    }

    static var configuration: PostgresClient.Configuration {
        let environment = ProcessInfo.processInfo.environment
        return PostgresClient.Configuration(
            host: environment["POSTGRES_HOST"] ?? "localhost",
            port: Int(environment["POSTGRES_PORT"] ?? "5432") ?? 5432,
            username: environment["POSTGRES_USER"] ?? "postgres",
            password: environment["POSTGRES_PASSWORD"],
            database: environment["POSTGRES_DATABASE"],
            tls: .disable
        )
    }
}
