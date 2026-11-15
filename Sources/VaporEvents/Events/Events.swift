import Logging
import Vapor
import VaporEventsCore

/// Owns the application's event bus and broadcast configuration.
///
/// Create one in `configure`, register it with the application lifecycle, and
/// pass it to the controllers that need it:
///
/// ```swift
/// let events = Events()
/// app.addLifecycleHandler(events)
/// try await routes(app, events: events)
/// ```
public final class Events: Sendable, LifecycleHandler {
    /// The application-wide event bus.
    public let bus: any EventBus

    /// The broadcast configuration.
    public let broadcast: Broadcast

    /// Creates an events holder.
    ///
    /// - Parameters:
    ///   - enqueuing: The handler used to enqueue ``ShouldQueue`` listeners.
    ///     Pass one when a queue integration is available.
    ///   - logger: The logger used for dispatch and broadcast diagnostics.
    public init(
        enqueuing: (any EventEnqueuing)? = nil,
        logger: Logger = Logger.current
    ) {
        // Build the dispatcher and expose it as the application's bus.
        let dispatcher = EventDispatcher(enqueuing: enqueuing, logger: logger)
        self.bus = dispatcher

        // Install the broadcast relay before listeners are registered, so it
        // observes every broadcast event type as it is added.
        if let observing = dispatcher as? (any EventBus & EventObserving) {
            let manager = BroadcastManager(dispatcher: observing, logger: logger)
            manager.start()
            self.broadcast = Broadcast(manager: manager)
        } else {
            self.broadcast = Broadcast(manager: nil)
        }
    }

    /// Stops the broadcast relay and releases its drivers.
    public func shutdown(_ application: Application) async {
        await self.broadcast.shutdown()
    }
}
