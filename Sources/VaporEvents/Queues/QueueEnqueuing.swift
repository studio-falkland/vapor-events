import Queues
import Synchronization
import Vapor
import VaporEventsCore

/// Enqueues ``ShouldQueue`` listeners with `vapor/queues`.
///
/// The enqueuing owns the queued listeners; the dispatcher never sees them.
final class QueueEnqueuing: EventEnqueuing {
    /// A queued listener and its priority.
    private struct Queued: Sendable {
        let priority: Int
        let listenerType: ObjectIdentifier
        let enqueue: @Sendable (any Event) async throws -> Void
    }

    /// The application, captured weakly to avoid a storage cycle.
    let application: @Sendable () -> Application?

    /// Queued listeners keyed by event type, sorted by priority.
    private let queued = Mutex<[ObjectIdentifier: [Queued]]>([:])

    /// Creates an enqueuing for an application.
    ///
    /// - Parameter application: The application, captured weakly.
    init(application: @escaping @Sendable () -> Application?) {
        self.application = application
    }

    /// Registers a queued listener as a job.
    ///
    /// A second instance of the same listener type is skipped, because the
    /// queue keys jobs by type and would run only the last one.
    ///
    /// - Parameter listener: The listener to register.
    func register<L: EventListener>(_ listener: L) {
        let eventKey = ObjectIdentifier(L.EventType.self)
        let listenerType = ObjectIdentifier(L.self)
        let listenerName = String(reflecting: L.self)

        // Reject a second instance of the same listener type.
        let isDuplicate = self.queued.withLock { state in
            (state[eventKey] ?? []).contains { $0.listenerType == listenerType }
        }
        guard !isDuplicate else {
            self.application()?.logger.error(
                "Skipping duplicate queued listener",
                metadata: [
                    "event": .string(L.EventType.name),
                    "listener": .string(listenerName),
                ]
            )
            return
        }

        self.application()?.logger.debug(
            "Registering queued listener",
            metadata: [
                "event": .string(L.EventType.name),
                "listener": .string(listenerName),
            ]
        )

        // Register the job with the queue.
        self.application()?.queues.add(ListenerJob(listener: listener))

        // Build the closure that enqueues the listener's event type.
        let application = self.application
        let enqueue: @Sendable (any Event) async throws -> Void = { event in
            guard let typed = event as? L.EventType else {
                throw EventError.typeMismatch(
                    expected: L.EventType.name,
                    actual: String(reflecting: type(of: event))
                )
            }
            guard let application = application() else { return }
            try await application.queues.queue.dispatch(ListenerJob<L>.self, typed)
        }

        // Insert the listener in priority order.
        self.queued.withLock { state in
            var list = state[eventKey] ?? []
            let index = list.firstIndex { $0.priority < L.priority } ?? list.endIndex
            list.insert(Queued(priority: L.priority, listenerType: listenerType, enqueue: enqueue), at: index)
            state[eventKey] = list
        }
    }

    /// Enqueues an event for every queued listener of its type.
    ///
    /// - Parameter event: The event to enqueue.
    func enqueue<E: Event>(_ event: E) async throws {
        // Snapshot the listeners for this event type, then enqueue outside the lock.
        let listeners = self.queued.withLock { $0[ObjectIdentifier(E.self)] ?? [] }
        self.application()?.logger.trace(
            "Enqueuing event for queued listeners",
            metadata: ["event": .string(E.name), "listeners": .stringConvertible(listeners.count)]
        )
        for listener in listeners {
            try await listener.enqueue(event)
        }
    }
}
