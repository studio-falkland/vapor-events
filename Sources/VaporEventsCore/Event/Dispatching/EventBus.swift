/// The application-wide bus for local event dispatch.
///
/// An event bus registers listeners and streams and dispatches events to them.
/// It does not handle cross-instance transport; that is the job of a
/// ``BroadcastRelay``.
public protocol EventBus: Sendable {
    /// Registers a listener for its event type.
    ///
    /// - Parameter listener: The listener to register.
    func listen<L: EventListener>(_ listener: L) async

    /// Registers a closure listener for an event type.
    ///
    /// - Parameters:
    ///   - eventType: The event type to listen for.
    ///   - priority: Higher values run first. Ties keep registration order.
    ///   - handler: The closure invoked for each event.
    func listen<E: Event>(
        _ eventType: E.Type,
        priority: Int,
        _ handler: @escaping @Sendable (E) async throws -> Void
    ) async

    /// Dispatches an event to its registered listeners.
    ///
    /// - Parameter event: The event to dispatch.
    /// - Throws: The first error thrown by a listener.
    func dispatch<E: Event>(_ event: E) async throws

    /// Creates a live stream of events.
    ///
    /// Each call returns an independent stream with its own buffer, so register
    /// one stream per consumer. Iterating the same stream from several tasks
    /// splits the events between them instead of copying them.
    ///
    /// - Parameters:
    ///   - eventType: The event type to stream.
    ///   - bufferingPolicy: How to buffer events for slow consumers.
    /// - Returns: A cancellable stream of events.
    func stream<E: Event>(
        _ eventType: E.Type,
        bufferingPolicy: AsyncStream<E>.Continuation.BufferingPolicy
    ) async -> AsyncStream<E>

    /// Receives an event without notifying observers.
    ///
    /// - Parameter event: The event to receive.
    func receive<E: Event>(_ event: E) async throws
}

/// Observes event type registrations and dispatches.
///
/// Observation is infrastructure for the broadcast relay. It is not part of the
/// public bus because relays are not an extension point; transports are.
package protocol EventObserving: Sendable {
    /// Registers an observer.
    ///
    /// - Parameter observer: The observer to add.
    /// - Returns: A cancellation that removes the observer.
    func observe(_ observer: any DispatchObserver) -> Cancellation
}

extension EventBus {
    /// Registers a closure listener with the default priority.
    ///
    /// - Parameters:
    ///   - eventType: The event type to listen for.
    ///   - handler: The closure invoked for each event.
    public func listen<E: Event>(
        _ eventType: E.Type,
        _ handler: @escaping @Sendable (E) async throws -> Void
    ) async {
        await self.listen(eventType, priority: 0, handler)
    }

    /// Creates a stream with the default buffering policy.
    ///
    /// Each call returns an independent stream with its own buffer, so register
    /// one stream per consumer.
    ///
    /// - Parameter eventType: The event type to stream.
    /// - Returns: A cancellable stream of events.
    public func stream<E: Event>(_ eventType: E.Type) async -> AsyncStream<E> {
        await self.stream(eventType, bufferingPolicy: .bufferingNewest(64))
    }
}
