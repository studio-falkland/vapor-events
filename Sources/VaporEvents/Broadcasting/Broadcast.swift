import Vapor
import VaporEventsCore

extension Application {
    /// A facade for the application's broadcast configuration.
    public struct Broadcast: Sendable {
        /// The application.
        public let application: Application

        /// Uses a driver as the default connection.
        ///
        /// - Parameter driver: The driver to use.
        /// - Returns: This facade, for chaining.
        @discardableResult
        public func use(_ driver: any BroadcastDriver) -> Self {
            self.broadcaster.use(driver)
            return self
        }

        /// Uses a driver factory as the default connection.
        ///
        /// - Parameter factory: The factory that builds the driver.
        /// - Returns: This facade, for chaining.
        @discardableResult
        public func use(_ factory: BroadcastDriverFactory) -> Self {
            self.use(factory.driver(for: self.application))
        }

        /// Registers a driver for a connection.
        ///
        /// - Parameters:
        ///   - connection: The connection to register.
        ///   - driver: The driver to use.
        /// - Returns: This facade, for chaining.
        @discardableResult
        public func register(_ connection: BroadcastConnection, _ driver: any BroadcastDriver) -> Self {
            self.broadcaster.register(connection, driver)
            return self
        }

        /// Registers a driver factory for a connection.
        ///
        /// - Parameters:
        ///   - connection: The connection to register.
        ///   - factory: The factory that builds the driver.
        /// - Returns: This facade, for chaining.
        @discardableResult
        public func register(_ connection: BroadcastConnection, _ factory: BroadcastDriverFactory) -> Self {
            self.register(connection, factory.driver(for: self.application))
        }

        /// Uses a registered connection as the default.
        ///
        /// - Parameter connection: The connection to use.
        /// - Returns: This facade, for chaining.
        @discardableResult
        public func useDefault(_ connection: BroadcastConnection) -> Self {
            self.broadcaster.useDefault(connection)
            return self
        }

        /// The application's broadcaster.
        private var broadcaster: Broadcaster {
            // Ensure the default manager exists.
            _ = self.application.events

            // Read the installed broadcaster.
            guard let manager = self.application.broadcastManager() else {
                preconditionFailure("The broadcast relay requires an observing event bus.")
            }
            return manager.broadcaster
        }
    }
}
