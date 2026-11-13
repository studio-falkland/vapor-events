import Logging
import Synchronization

/// Owns the broadcast connections and the drivers registered for them.
///
/// The broadcaster resolves the connection for an event type, then publishes
/// and subscribes through the driver registered for that connection. The
/// in-process driver is registered for both ``BroadcastConnection/inProcess``
/// and ``BroadcastConnection/default`` at creation.
package final class Broadcaster: Sendable {
    /// The state shared by concurrent calls.
    private struct State: Sendable {
        /// Drivers keyed by connection.
        var drivers: [BroadcastConnection: any BroadcastDriver]

        /// Drivers pinned to event types.
        var resolved: [ObjectIdentifier: any BroadcastDriver] = [:]
    }

    /// The broadcaster state.
    private let state: Mutex<State>

    /// The logger used for broadcast diagnostics.
    private let logger: Logger

    /// Creates a broadcaster with the in-process driver registered.
    ///
    /// - Parameter logger: The logger used for broadcast diagnostics.
    package init(logger: Logger = Logger(label: "vapor-events.broadcaster")) {
        self.logger = logger

        // Share one in-process driver between the default and explicit connection.
        let inProcess = InProcessBroadcastDriver(logger: logger)
        self.state = Mutex(State(drivers: [
            .inProcess: inProcess,
            .default: inProcess,
        ]))
    }

    /// Registers a driver for a connection.
    ///
    /// - Parameters:
    ///   - connection: The connection to register.
    ///   - driver: The driver to use.
    package func register(_ connection: BroadcastConnection, _ driver: any BroadcastDriver) {
        self.logger.debug(
            "Registering broadcast driver",
            metadata: ["connection": .string(connection.rawValue)]
        )
        self.state.withLock { state in
            state.drivers[connection] = driver
        }
    }

    /// Uses a driver as the default connection.
    ///
    /// - Parameter driver: The driver to use.
    package func use(_ driver: any BroadcastDriver) {
        self.logger.debug("Using driver as the default connection")
        self.state.withLock { state in
            state.drivers[.default] = driver
        }
    }

    /// Uses a registered connection as the default.
    ///
    /// - Parameter connection: The connection to use.
    package func useDefault(_ connection: BroadcastConnection) {
        self.logger.debug(
            "Using connection as the default",
            metadata: ["connection": .string(connection.rawValue)]
        )
        self.state.withLock { state in
            guard let driver = state.drivers[connection] else {
                preconditionFailure("No driver is registered for the \(connection) connection.")
            }
            state.drivers[.default] = driver
        }
    }

    /// Publishes an envelope with the driver for its event type.
    ///
    /// - Parameter envelope: The envelope to publish.
    package func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws {
        self.logger.trace("Publishing envelope", metadata: ["event": .string(E.name)])
        let driver = self.driver(for: E.self)
        try await driver.publish(envelope)
    }

    /// Subscribes to an event type with its driver.
    ///
    /// - Parameter type: The event type to subscribe to.
    /// - Returns: A cancellable subscription.
    package func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E> {
        self.logger.trace("Subscribing to event", metadata: ["event": .string(E.name)])
        let driver = self.driver(for: E.self)
        return await driver.subscribe(to: type)
    }

    /// Shuts down every registered driver.
    package func shutdown() async {
        // Take the drivers and reset the state.
        let drivers = self.state.withLock { state -> [any BroadcastDriver] in
            defer {
                state.drivers.removeAll()
                state.resolved.removeAll()
            }
            return Array(state.drivers.values)
        }

        self.logger.debug(
            "Shutting down broadcaster",
            metadata: ["drivers": .stringConvertible(drivers.count)]
        )

        // Shut down each unique driver.
        var seen = Set<ObjectIdentifier>()
        for driver in drivers {
            let id = ObjectIdentifier(driver as AnyObject)
            guard seen.insert(id).inserted else { continue }
            await driver.shutdown()
        }
    }

    /// Returns the driver for an event type, pinning it on first use.
    ///
    /// - Parameter type: The event type.
    /// - Returns: The driver for the event type's connection.
    private func driver<E: Event>(for type: E.Type) -> any BroadcastDriver {
        self.state.withLock { state in
            // Reuse the pinned driver.
            let key = ObjectIdentifier(E.self)
            if let pinned = state.resolved[key] {
                return pinned
            }

            // Resolve the event's connection, falling back to the default.
            let connection = (E.self as? any ShouldBroadcast.Type)?.broadcastConnection ?? .default
            guard let driver = state.drivers[connection] else {
                preconditionFailure("No driver is registered for the \(connection) connection.")
            }
            self.logger.debug(
                "Resolved broadcast connection",
                metadata: ["event": .string(E.name), "connection": .string(connection.rawValue)]
            )

            // Pin the driver for this event type.
            state.resolved[key] = driver
            return driver
        }
    }
}
