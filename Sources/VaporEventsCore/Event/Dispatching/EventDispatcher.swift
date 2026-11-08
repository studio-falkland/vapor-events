#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// The production ``EventBus``.
///
/// The dispatcher is an actor, so registration and dispatch are safe from any
/// thread. Listeners run sequentially in priority order; the first error stops
/// dispatch and is rethrown. Streams are fed after listeners.
public actor EventDispatcher: EventBus, EventObserving {
    /// A type-erased listener registration.
    struct Registration: Sendable {
        let eventName: String
        let listenerName: String
        let priority: Int
        let handle: @Sendable (any Event) async throws -> Void
    }

    /// Registrations keyed by event type, sorted by priority.
    var registrations: [ObjectIdentifier: [Registration]] = [:]

    /// Multicast channels keyed by event type.
    private var channels: [ObjectIdentifier: any AnyMulticast] = [:]

    /// Observers of registrations and dispatches.
    private let observers = ObserverSet<any DispatchObserver>()

    /// Event types that have already been registered.
    private var registeredEventTypes: Set<ObjectIdentifier> = []

    /// Creates a dispatcher.
    public init() {}

    /// Registers a listener for its event type.
    ///
    /// - Parameter listener: The listener to register.
    public func listen<L: EventListener>(_ listener: L) async {
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

        // Insert the registration and notify observers.
        self.add(registration, for: ObjectIdentifier(L.EventType.self))
        await self.notifyRegistered(L.EventType.self)
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
    ) async {
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

        // Insert the registration and notify observers.
        self.add(registration, for: ObjectIdentifier(E.self))
        await self.notifyRegistered(E.self)
    }

    /// Creates a live stream of events.
    ///
    /// - Parameters:
    ///   - eventType: The event type to stream.
    ///   - bufferingPolicy: How to buffer events for slow consumers.
    /// - Returns: A cancellable stream of events.
    public func stream<E: Event>(
        _ eventType: E.Type,
        bufferingPolicy: AsyncStream<E>.Continuation.BufferingPolicy
    ) async -> AsyncStream<E> {
        // Create the subscriber stream before notifying, so events dispatched
        // during notification are still buffered for this subscriber.
        let stream = self.channel(for: E.self).subscribe(bufferingPolicy: bufferingPolicy).stream

        // Notify observers of the event type.
        await self.notifyRegistered(E.self)

        return stream
    }

    /// Dispatches an event to its registered listeners.
    ///
    /// Listeners run in priority order. The first error stops dispatch and is
    /// rethrown.
    ///
    /// - Parameter event: The event to dispatch.
    /// - Throws: The first error thrown by a listener.
    public func dispatch<E: Event>(_ event: E) async throws {
        // Run listeners and streams.
        try await self.deliver(event)

        // Notify observers after delivery.
        await self.notifyDispatched(event)
    }

    /// Receives an event without notifying observers.
    ///
    /// - Parameter event: The event to receive.
    public func receive<E: Event>(_ event: E) async throws {
        // Run listeners and streams.
        try await self.deliver(event)
    }

    /// Observes registrations and dispatches with an observer.
    ///
    /// - Parameter observer: The observer to add.
    /// - Returns: A cancellation that removes the observer.
    nonisolated package func observe(_ observer: any DispatchObserver) -> Cancellation {
        // Register the observer and hand back its cancellation.
        self.observers.add(observer, id: ObjectIdentifier(observer))
    }

    /// Returns the multicast channel for an event type, creating it if needed.
    private func channel<E: Event>(for type: E.Type) -> Multicast<E> {
        // Reuse the existing channel for the type.
        let key = ObjectIdentifier(E.self)
        if let existing = self.channels[key] as? Multicast<E> {
            return existing
        }

        // Create and store a new channel.
        let channel = Multicast<E>()
        self.channels[key] = channel
        return channel
    }

    /// Runs listeners and streams for an event.
    private func deliver<E: Event>(_ event: E) async throws {
        // Copy the registrations for this dispatch.
        let registrations = self.registrations[ObjectIdentifier(E.self)] ?? []

        // Run listeners in order; the first error stops dispatch.
        for registration in registrations {
            try await registration.handle(event)
        }

        // Feed live streams after listeners.
        if let channel = self.channels[ObjectIdentifier(E.self)] as? Multicast<E> {
            channel.send(event)
        }
    }

    /// Notifies observers of a new event type.
    private func notifyRegistered<E: Event>(_ type: E.Type) async {
        // Notify only the first time the event type is registered.
        guard self.registeredEventTypes.insert(ObjectIdentifier(E.self)).inserted else { return }

        // Notify every observer.
        for observer in self.observers.snapshot {
            await observer.registered(E.self)
        }
    }

    /// Notifies observers of a dispatch.
    private func notifyDispatched<E: Event>(_ event: E) async {
        // Notify every observer.
        for observer in self.observers.snapshot {
            await observer.dispatched(event)
        }
    }

    /// Inserts a registration in priority order.
    private func add(_ registration: Registration, for type: ObjectIdentifier) {
        // Find the first listener with a lower priority.
        var list = self.registrations[type, default: []]
        let index = list.firstIndex { $0.priority < registration.priority } ?? list.endIndex

        // Insert after any equal-priority listeners.
        list.insert(registration, at: index)
        self.registrations[type] = list
    }
}
