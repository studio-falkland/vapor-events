import Vapor
import VaporEventsCore

extension Application {
    /// A facade for the application's broadcast relay.
    public struct Broadcast: Sendable {
        /// The application.
        public let application: Application

        /// Configures broadcasting with a driver.
        ///
        /// Register broadcasting before adding listeners, so the relay observes
        /// every broadcast event type as it is registered.
        ///
        /// - Parameter driver: The driver to use.
        public func use(_ driver: any BroadcastDriver) {
            self.install(driver)
        }

        /// Configures broadcasting with a driver factory.
        ///
        /// Register broadcasting before adding listeners, so the relay observes
        /// every broadcast event type as it is registered.
        ///
        /// - Parameter factory: The factory that builds the driver.
        public func use(_ factory: BroadcastDriverFactory) {
            self.install(factory.driver(for: self.application))
        }

        /// Creates and starts the relay for a driver.
        ///
        /// - Parameter driver: The driver to use.
        private func install(_ driver: any BroadcastDriver) {
            // Create the relay once.
            self.application.locks.lock(for: BroadcastRelayKey.self).withLock {
                precondition(
                    self.application.storage[BroadcastRelayKey.self] == nil,
                    "The broadcast relay has already been created."
                )

                // The relay needs a bus it can observe.
                guard let dispatcher = self.application.events as? (any EventBus & EventObserving) else {
                    preconditionFailure("The broadcast relay requires an observing event bus.")
                }

                // Create, store, and start the relay.
                let relay = BroadcastRelay(
                    driver: driver,
                    dispatcher: dispatcher,
                    logger: self.application.logger
                )
                self.application.storage[BroadcastRelayKey.self] = relay
                relay.start()

                // Stop the relay and release the driver with the application.
                self.application.lifecycle.use(BroadcastShutdown(relay: relay, driver: driver))
            }
        }
    }
}
