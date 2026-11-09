#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import Testing
import Valkey
import VaporEventsCore
@testable import VaporEventsValkey

struct BroadcastEvent: Event {
    let id: UUID
}

@Suite("ValkeyBroadcastDriver", .enabled(if: ValkeyTestEnvironment.isConfigured))
struct ValkeyBroadcastDriverTests {
    @Test
    func publishesAndReceives() async throws {
        // Create the client and run it in the background.
        let logger = Logger(label: "test")
        let client = ValkeyClient(
            .hostname(ValkeyTestEnvironment.host, port: ValkeyTestEnvironment.port),
            logger: logger
        )
        let clientTask = Task { await client.run() }

        // Create a broadcaster and subscribe.
        let driver = ValkeyBroadcastDriver(
            client: client,
            channelPrefix: "vapor_events_test",
            logger: logger
        )
        let subscription = await driver.subscribe(to: BroadcastEvent.self)

        // Publish until the asynchronous subscription is live.
        let event = BroadcastEvent(id: UUID())
        let envelope = EventEnvelope(event: event, origin: "origin")
        let received = await self.waitForEnvelope(from: subscription) {
            try? await driver.publish(envelope)
        }
        #expect(received?.event.id == event.id)

        // Clean up.
        subscription.cancel()
        await driver.shutdown()
        clientTask.cancel()
    }

    /// Returns the first envelope received, republishing until one arrives.
    private func waitForEnvelope(
        from subscription: EventSubscription<BroadcastEvent>,
        publishing: @escaping @Sendable () async -> Void
    ) async -> EventEnvelope<BroadcastEvent>? {
        await withTaskGroup(of: EventEnvelope<BroadcastEvent>?.self) { group in
            group.addTask {
                for await envelope in subscription {
                    return envelope
                }
                return nil
            }
            group.addTask {
                // Republishing covers the window before `SUBSCRIBE` is active.
                for _ in 0..<50 {
                    await publishing()
                    try? await Task.sleep(for: .milliseconds(100))
                }
                return nil
            }
            let result = await group.next() ?? nil
            group.cancelAll()
            return result
        }
    }
}

@Suite("ValkeyBroadcastDriver channel names")
struct ValkeyBroadcastChannelTests {
    @Test
    func sanitizesEventNames() {
        let channel = ValkeyBroadcastDriver.channelName(
            prefix: "vapor_events",
            event: "App.Order.Created"
        )
        #expect(channel == "vapor_events:app_order_created")
    }
}

private enum ValkeyTestEnvironment {
    static var isConfigured: Bool {
        ProcessInfo.processInfo.environment["VALKEY_HOST"] != nil
    }

    static var host: String {
        ProcessInfo.processInfo.environment["VALKEY_HOST"] ?? "localhost"
    }

    static var port: Int {
        Int(ProcessInfo.processInfo.environment["VALKEY_PORT"] ?? "6379") ?? 6379
    }
}
