import PostgresNIO
import Vapor
import VaporEvents

extension BroadcastDriverFactory {
    /// A driver backed by an existing Postgres client.
    ///
    /// The application owns the client: it must run the client and stop it. The
    /// client's pool must accommodate one connection per broadcast event type,
    /// because each subscription holds a `LISTEN` connection.
    ///
    /// - Parameters:
    ///   - client: The client to publish and listen with.
    ///   - channelPrefix: The prefix used to build per-event channel names.
    /// - Returns: A factory for the Postgres driver.
    public static func postgres(
        client: PostgresClient,
        channelPrefix: String = "vapor_events"
    ) -> Self {
        Self { application in
            PostgresBroadcastDriver(
                client: client,
                channelPrefix: channelPrefix,
                logger: application.logger
            )
        }
    }

    /// A driver backed by Postgres `LISTEN`/`NOTIFY`.
    ///
    /// Creates a dedicated client, runs it for the lifetime of the application,
    /// and stops it on shutdown.
    ///
    /// - Parameters:
    ///   - configuration: The Postgres client configuration.
    ///   - channelPrefix: The prefix used to build per-event channel names.
    /// - Returns: A factory for the Postgres driver.
    public static func postgres(
        configuration: PostgresClient.Configuration,
        channelPrefix: String = "vapor_events"
    ) -> Self {
        Self { application in
            // Create the client and start it immediately, so subscriptions made
            // during configuration can lease connections.
            let client = PostgresClient(
                configuration: configuration,
                backgroundLogger: application.logger
            )
            application.lifecycle.use(PostgresClientLifecycle(client: client))

            // Return a driver that shares the client.
            return PostgresBroadcastDriver(
                client: client,
                channelPrefix: channelPrefix,
                logger: application.logger
            )
        }
    }
}

/// Stops a Postgres client with the application lifecycle.
private final class PostgresClientLifecycle: LifecycleHandler {
    /// The task running the client.
    private let task: Task<Void, Never>

    init(client: PostgresClient) {
        // Start the client; its task ends when the application shuts down.
        self.task = Task {
            await client.run()
        }
    }

    func shutdownAsync(_ application: Application) async {
        // Stop the client.
        self.task.cancel()
    }
}
