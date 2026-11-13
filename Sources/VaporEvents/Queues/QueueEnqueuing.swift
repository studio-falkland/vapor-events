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
    /// - Parameter listener: The listener to register.
    func register<L: EventListener>(_ listener: L) {
        self.application()?.logger.debug(
            "Registering queued listener",
            metadata: [
                "event": .string(L.EventType.name),
                "listener": .string(String(reflecting: L.self)),
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
            var list = state[ObjectIdentifier(L.EventType.self)] ?? []
            let index = list.firstIndex { $0.priority < L.priority } ?? list.endIndex
            list.insert(Queued(priority: L.priority, enqueue: enqueue), at: index)
            state[ObjectIdentifier(L.EventType.self)] = list
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
