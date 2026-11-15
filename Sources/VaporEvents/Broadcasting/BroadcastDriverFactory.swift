import Logging
import VaporEventsCore

/// Constructs a ``BroadcastDriver`` for an application.
///
/// Factories are registered with `events.broadcast.use(...)` and are only
/// invoked when the driver is first needed. This lets a factory use the
/// application logger without requiring an `Application` reference.
public struct BroadcastDriverFactory: Sendable {
    /// Builds the driver with the supplied logger.
    private let make: @Sendable (Logger) -> any BroadcastDriver

    /// Creates a new factory.
    ///
    /// - Parameter make: A closure that constructs the driver.
    public init(_ make: @escaping @Sendable (Logger) -> any BroadcastDriver) {
        self.make = make
    }

    /// Builds the driver.
    ///
    /// - Parameter logger: The logger used for transport diagnostics.
    /// - Returns: The configured driver.
    public func driver(logger: Logger = Logger.current) -> any BroadcastDriver {
        self.make(logger)
    }
}
