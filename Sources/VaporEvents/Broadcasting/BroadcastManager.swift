import Logging
import VaporEventsCore

/// Owns the broadcaster and the relay that connects it to the event bus.
package final class BroadcastManager: Sendable {
    /// The driver registry.
    let broadcaster: Broadcaster

    /// The relay observing the event bus.
    let relay: BroadcastRelay

    /// The logger used for broadcast diagnostics.
    private let logger: Logger

    /// Creates a broadcast manager.
    ///
    /// - Parameters:
    ///   - dispatcher: The dispatcher the relay observes.
    ///   - logger: The logger used for transport failures.
    package init(dispatcher: any EventBus & EventObserving, logger: Logger) {
        self.logger = logger
        let broadcaster = Broadcaster(logger: logger)
        self.broadcaster = broadcaster
        self.relay = BroadcastRelay(
            broadcaster: broadcaster,
            dispatcher: dispatcher,
            logger: logger
        )
    }

    /// Starts observing the event bus.
    package func start() {
        self.logger.debug("Starting broadcast manager")
        self.relay.start()
    }

    /// Stops observing and releases the drivers.
    package func shutdown() async {
        self.logger.debug("Shutting down broadcast manager")
        self.relay.shutdown()
        await self.broadcaster.shutdown()
    }
}
