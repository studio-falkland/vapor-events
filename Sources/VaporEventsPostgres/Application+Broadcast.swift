import Logging
import PostgresNIO
import VaporEvents

extension BroadcastDriverFactory {
    /// A driver backed by an existing Postgres client.
    ///
    /// The application owns the client: it must run the client and stop it. The
    /// driver holds one `LISTEN` connection for its lifetime.
    ///
    /// - Parameters:
    ///   - client: The client to publish and listen with.
    ///   - channel: The `LISTEN`/`NOTIFY` channel used for every event type.
    /// - Returns: A factory for the Postgres driver.
    public static func postgres(
        client: PostgresClient,
        channel: String = "vapor_events"
    ) -> Self {
        Self { logger in
            PostgresBroadcastDriver(
                client: client,
                channel: channel,
                logger: logger
            )
        }
    }

    /// A driver backed by Postgres `LISTEN`/`NOTIFY`.
    ///
    /// The driver creates and runs its own client, and stops it on shutdown.
    ///
    /// - Parameters:
    ///   - configuration: The Postgres client configuration.
    ///   - channel: The `LISTEN`/`NOTIFY` channel used for every event type.
    /// - Returns: A factory for the Postgres driver.
    public static func postgres(
        configuration: PostgresClient.Configuration,
        channel: String = "vapor_events"
    ) -> Self {
        Self { logger in
            PostgresBroadcastDriver(
                configuration: configuration,
                channel: channel,
                logger: logger
            )
        }
    }
}

extension BroadcastConnection {
    /// The Postgres `LISTEN`/`NOTIFY` connection.
    public static let postgres = Self(rawValue: "postgres")
}
