#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Registers listeners and dispatches events.
public actor EventDispatcher {
    /// A type-erased listener registration.
    private struct Registration: Sendable {
        let eventName: String
        let listenerName: String
        let priority: Int
        let handle: @Sendable (any Event) async throws -> Void
    }

    /// Registrations keyed by event name, sorted by priority.
    private var registrations: [String: [Registration]] = [:]

    /// A type-erased stream registration.
    private struct StreamRegistration: Sendable {
        let id: UUID
        let yield: @Sendable (any Event) -> Void
    }

    /// Streams keyed by event name.
    private var streams: [String: [StreamRegistration]] = [:]

    /// Creates a dispatcher.
    public init() {}

    /// Registers a listener for its event type.
    ///
    /// - Parameter listener: The listener to register.
    public func listen<L: EventListener>(_ listener: L) {
        // Resolve the event name and listener identity.
        let eventName = L.EventType.name
        let listenerName = String(reflecting: L.self)

        // Capture the listener and cast incoming events back to its type.
        let handle: @Sendable (any Event) async throws -> Void = { event in
            guard let typed = event as? L.EventType else {
                throw EventError.typeMismatch(
                    expected: eventName,
                    actual: String(reflecting: type(of: event))
                )
            }
            try await listener.handle(typed)
        }

        // Build the registration.
        let registration = Registration(
            eventName: eventName,
            listenerName: listenerName,
            priority: L.priority,
            handle: handle
        )

        // Insert the registration in priority order.
        self.add(registration, for: eventName)
    }

    /// Registers a closure listener for an event type.
    ///
    /// - Parameters:
    ///   - eventType: The event type to listen for.
    ///   - priority: Higher values run first. Ties keep registration order.
    ///   - handler: The closure invoked for each event.
    public func listen<E: Event>(
        _ eventType: E.Type,
        priority: Int = 0,
        _ handler: @escaping @Sendable (E) async throws -> Void
    ) {
        // Resolve the event name and a unique listener identity.
        let eventName = E.name
        let listenerName = "closure:\(eventName):\(UUID().uuidString)"

        // Cast incoming events back to the closure's event type.
        let handle: @Sendable (any Event) async throws -> Void = { event in
            guard let typed = event as? E else {
                throw EventError.typeMismatch(
                    expected: eventName,
                    actual: String(reflecting: type(of: event))
                )
            }
            try await handler(typed)
        }

        // Build the registration.
        let registration = Registration(
            eventName: eventName,
            listenerName: listenerName,
            priority: priority,
            handle: handle
        )

        // Insert the registration in priority order.
        self.add(registration, for: eventName)
    }

    /// Creates a live stream of events.
    ///
    /// - Parameters:
    ///   - eventType: The event type to stream.
    ///   - bufferingPolicy: How to buffer events for slow consumers.
    /// - Returns: A cancellable stream of events.
    public func stream<E: Event>(
        _ eventType: E.Type,
        bufferingPolicy: AsyncStream<E>.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> EventStream<E> {
        // Create the stream and its continuation.
        let id = UUID()
        let (stream, continuation) = AsyncStream<E>.makeStream(bufferingPolicy: bufferingPolicy)

        // Register a type-erased yield closure.
        let registration = StreamRegistration(
            id: id,
            yield: { event in
                guard let typed = event as? E else { return }
                continuation.yield(typed)
            }
        )
        self.streams[E.name, default: []].append(registration)

        // Remove the registration when the stream terminates.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.removeStream(id: id, for: E.name) }
        }

        // Return a cancellable stream.
        return EventStream(stream: stream) {
            continuation.finish()
        }
    }

    /// Dispatches an event to its registered listeners.
    ///
    /// Listeners run in priority order. The first error stops dispatch and is
    /// rethrown.
    ///
    /// - Parameter event: The event to dispatch.
    /// - Throws: The first error thrown by a listener.
    public func dispatch<E: Event>(_ event: E) async throws {
        // Copy the registrations for this dispatch.
        let registrations = self.registrations[E.name] ?? []

        // Run listeners in order; the first error stops dispatch.
        for registration in registrations {
            try await registration.handle(event)
        }

        // Feed live streams after listeners.
        let streams = self.streams[E.name] ?? []
        for stream in streams {
            stream.yield(event)
        }
    }

    /// Inserts a registration in priority order.
    private func add(_ registration: Registration, for eventName: String) {
        // Find the first listener with a lower priority.
        var list = self.registrations[eventName, default: []]
        let index = list.firstIndex { $0.priority < registration.priority } ?? list.endIndex

        // Insert after any equal-priority listeners.
        list.insert(registration, at: index)
        self.registrations[eventName] = list
    }

    /// Removes a stream registration.
    private func removeStream(id: UUID, for eventName: String) {
        // Drop the registration with the matching identifier.
        guard var list = self.streams[eventName] else { return }
        list.removeAll { $0.id == id }
        self.streams[eventName] = list
    }
}
