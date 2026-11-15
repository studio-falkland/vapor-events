import VaporEventsCore

/// A facade for the application's broadcast configuration.
///
/// Obtain one from ``Events/broadcast`` and register drivers before listeners
/// are added:
///
/// ```swift
/// events.broadcast.use(.postgres(configuration: configuration))
/// ```
public struct Broadcast: Sendable {
    /// The manager that owns the broadcaster and relay.
    private let manager: BroadcastManager?

    /// Creates a facade over a broadcast manager.
    init(manager: BroadcastManager?) {
        self.manager = manager
    }

    /// Uses a driver as the default connection.
    ///
    /// - Parameter driver: The driver to use.
    /// - Returns: This facade, for chaining.
    @discardableResult
    public func use(_ driver: any BroadcastDriver) -> Self {
        self.manager?.broadcaster.use(driver)
        return self
    }

    /// Uses a driver factory as the default connection.
    ///
    /// - Parameter factory: The factory that builds the driver.
    /// - Returns: This facade, for chaining.
    @discardableResult
    public func use(_ factory: BroadcastDriverFactory) -> Self {
        self.use(factory.driver())
    }

    /// Registers a driver for a connection.
    ///
    /// - Parameters:
    ///   - connection: The connection to register.
    ///   - driver: The driver to use.
    /// - Returns: This facade, for chaining.
    @discardableResult
    public func register(_ connection: BroadcastConnection, _ driver: any BroadcastDriver) -> Self {
        self.manager?.broadcaster.register(connection, driver)
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
        self.register(connection, factory.driver())
    }

    /// Uses a registered connection as the default.
    ///
    /// - Parameter connection: The connection to use.
    /// - Returns: This facade, for chaining.
    @discardableResult
    public func useDefault(_ connection: BroadcastConnection) -> Self {
        self.manager?.broadcaster.useDefault(connection)
        return self
    }

    /// Stops the relay and releases the drivers.
    func shutdown() async {
        await self.manager?.shutdown()
    }
}
