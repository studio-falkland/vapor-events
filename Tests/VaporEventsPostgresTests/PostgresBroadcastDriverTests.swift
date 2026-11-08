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

@Suite("PostgresBroadcastDriver", .enabled(if: PostgresTestEnvironment.isConfigured))
struct PostgresBroadcastDriverTests {
    @Test
    func publishesAndReceives() async throws {
        // Create and run a client.
        let client = PostgresClient(
            configuration: PostgresTestEnvironment.configuration,
            backgroundLogger: Logger(label: "test")
        )
        let clientTask = Task { await client.run() }
        defer { clientTask.cancel() }

        // Create a broadcaster and subscribe.
        let broadcaster = PostgresBroadcastDriver(client: client)
        let subscription = await broadcaster.subscribe(to: BroadcastEvent.self)

        // Publish an envelope.
        let event = BroadcastEvent(id: UUID())
        let envelope = EventEnvelope(event: event, origin: "origin")
        try await broadcaster.publish(envelope)

        // Read the envelope with a timeout.
        let received = await withTaskGroup(of: EventEnvelope<BroadcastEvent>?.self) { group in
            group.addTask {
                var iterator = subscription.makeAsyncIterator()
                return await iterator.next()
            }
            group.addTask {
                try? await Task.sleep(for: .seconds(5))
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
        #expect(received?.event.id == event.id)

        // Clean up.
        subscription.cancel()
        await broadcaster.shutdown()
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
