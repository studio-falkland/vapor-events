import Valkey
import Vapor
import VaporEvents

extension BroadcastDriverFactory {
    /// A driver backed by Valkey pub/sub.
    ///
    /// The application owns the client: it must create it and run its background
    /// process, for example with `async let _ = client.run()` or
    /// swift-service-lifecycle. `ValkeyClient` and `ValkeyClusterClient` both
    /// work; the client keeps the subscription on its own connection.
    ///
    /// Valkey compatible databases work too: valkey-swift speaks RESP3, which
    /// Redis has supported since version 6.
    ///
    /// - Parameters:
    ///   - client: The running client to publish and subscribe with.
    ///   - channelPrefix: The prefix used to build per-event channel names.
    /// - Returns: A factory for the Valkey driver.
    public static func valkey(
        client: any ValkeyClientProtocol,
        channelPrefix: String = "vapor_events"
    ) -> Self {
        Self { application in
            ValkeyBroadcastDriver(
                client: client,
                channelPrefix: channelPrefix,
                logger: application.logger
            )
        }
    }
}
