/// Dispatches events to listeners and streams.
public protocol EventDispatching: Sendable {
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
    /// - Parameters:
    ///   - eventType: The event type to stream.
    ///   - bufferingPolicy: How to buffer events for slow consumers.
    /// - Returns: A cancellable stream of events.
    func stream<E: Event>(
        _ eventType: E.Type,
        bufferingPolicy: AsyncStream<E>.Continuation.BufferingPolicy
    ) async -> EventStream<E>

    /// Starts receiving broadcast events.
    func start() async

    /// Stops receiving broadcast events.
    func shutdown() async
}

extension EventDispatching {
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
    /// - Parameter eventType: The event type to stream.
    /// - Returns: A cancellable stream of events.
    public func stream<E: Event>(_ eventType: E.Type) async -> EventStream<E> {
        await self.stream(eventType, bufferingPolicy: .bufferingNewest(64))
    }
}
