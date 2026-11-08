import Vapor
import VaporEventsCore

/// A deferred broadcast driver configuration.
///
/// Driver modules provide factories as static members, so an application can be
/// configured with `app.broadcast.use(.postgres(...))`.
public struct BroadcastDriverFactory: Sendable {
    /// Builds the driver for an application.
    private let make: @Sendable (Application) -> any BroadcastDriver

    /// Creates a factory.
    ///
    /// - Parameter make: A closure that builds the driver.
    public init(_ make: @escaping @Sendable (Application) -> any BroadcastDriver) {
        self.make = make
    }

    /// Builds the driver for an application.
    ///
    /// - Parameter application: The application the driver belongs to.
    /// - Returns: The broadcast driver.
    public func driver(for application: Application) -> any BroadcastDriver {
        self.make(application)
    }
}
