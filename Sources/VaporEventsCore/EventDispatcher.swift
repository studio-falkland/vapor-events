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
}
