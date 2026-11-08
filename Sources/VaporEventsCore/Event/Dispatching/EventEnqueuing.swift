/// Enqueues ``ShouldQueue`` listeners instead of running them during dispatch.
///
/// The Vapor adapter supplies an implementation backed by `vapor/queues`.
/// Pass one to ``EventDispatcher/init(enqueuing:)`` when using the core
/// without the adapter.
public protocol EventEnqueuing: Sendable {
    /// Registers a queued listener so the queue can run it later.
    ///
    /// - Parameter listener: The listener to register.
    func register<L: EventListener>(_ listener: L)

    /// Enqueues an event for every queued listener of its type.
    ///
    /// - Parameter event: The event to enqueue.
    func enqueue<E: Event>(_ event: E) async throws
}
