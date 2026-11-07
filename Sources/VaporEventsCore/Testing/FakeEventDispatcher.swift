#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Records dispatches instead of running listeners and streams.
public actor FakeEventDispatcher: EventDispatching {
    /// Events recorded in dispatch order.
    private var recorded: [any Event] = []

    /// Registered listener names keyed by event name.
    private var registrations: [String: [String]] = [:]

    /// Creates a fake dispatcher.
    public init() {}

    /// Registers a listener for its event type.
    ///
    /// - Parameter listener: The listener to register.
    public func listen<L: EventListener>(_ listener: L) {
        // Resolve the event name and listener identity.
        let eventName = L.EventType.name
        let listenerName = String(reflecting: L.self)

        // Record the registration.
        self.registrations[eventName, default: []].append(listenerName)
    }

    /// Registers a closure listener for an event type.
    ///
    /// - Parameters:
    ///   - eventType: The event type to listen for.
    ///   - priority: Ignored by the fake dispatcher.
    ///   - handler: Ignored by the fake dispatcher.
    public func listen<E: Event>(
        _ eventType: E.Type,
        priority: Int,
        _ handler: @escaping @Sendable (E) async throws -> Void
    ) {
        // Record a unique closure listener name.
        let eventName = E.name
        let listenerName = "closure:\(eventName):\(UUID().uuidString)"
        self.registrations[eventName, default: []].append(listenerName)
    }

    /// Records an event instead of dispatching it.
    ///
    /// - Parameter event: The event to record.
    public func dispatch<E: Event>(_ event: E) async throws {
        self.recorded.append(event)
    }

    /// Returns a finished stream.
    ///
    /// - Parameters:
    ///   - eventType: The event type to stream.
    ///   - bufferingPolicy: Ignored by the fake dispatcher.
    /// - Returns: An empty stream.
    public func stream<E: Event>(
        _ eventType: E.Type,
        bufferingPolicy: AsyncStream<E>.Continuation.BufferingPolicy
    ) -> EventStream<E> {
        // Create and immediately finish the stream.
        let (stream, continuation) = AsyncStream<E>.makeStream(bufferingPolicy: bufferingPolicy)
        continuation.finish()
        return EventStream(stream: stream) {}
    }

    /// Returns the recorded events of a type.
    ///
    /// - Parameter eventType: The event type to return.
    /// - Returns: The recorded events, in dispatch order.
    public func dispatched<E: Event>(_ eventType: E.Type) -> [E] {
        self.recorded.compactMap { $0 as? E }
    }

    /// Asserts that at least one event of a type was recorded.
    ///
    /// - Parameters:
    ///   - eventType: The event type to check.
    ///   - check: An optional predicate the event must satisfy.
    /// - Throws: ``EventAssertionError/notDispatched(_:)`` when no event matches.
    public func assertDispatched<E: Event>(
        _ eventType: E.Type,
        _ check: ((E) -> Bool)? = nil
    ) throws {
        let events = self.dispatched(eventType)
        guard events.contains(where: { check?($0) ?? true }) else {
            throw EventAssertionError.notDispatched(String(reflecting: E.self))
        }
    }

    /// Asserts that no event of a type was recorded.
    ///
    /// - Parameter eventType: The event type to check.
    /// - Throws: ``EventAssertionError/dispatched(_:)`` when an event was recorded.
    public func assertNotDispatched<E: Event>(_ eventType: E.Type) throws {
        guard self.dispatched(eventType).isEmpty else {
            throw EventAssertionError.dispatched(String(reflecting: E.self))
        }
    }

    /// Asserts that a listener is registered.
    ///
    /// - Parameter listener: The listener type to check.
    /// - Throws: ``EventAssertionError/listenerNotRegistered(_:)`` when it is not registered.
    public func assertListening<L: EventListener>(_ listener: L.Type) throws {
        let eventName = L.EventType.name
        let listenerName = String(reflecting: L.self)
        let registered = (self.registrations[eventName] ?? []).contains { $0 == listenerName }
        guard registered else {
            throw EventAssertionError.listenerNotRegistered(listenerName)
        }
    }

    /// Clears recorded events and registrations.
    public func reset() {
        self.recorded.removeAll()
        self.registrations.removeAll()
    }
}
