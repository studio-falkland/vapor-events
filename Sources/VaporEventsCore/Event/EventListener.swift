/// Handles one event type.
///
/// Listeners are registered with an ``EventBus``. They run in priority order
/// and are `Sendable`, so they can be invoked from any thread. Dependencies
/// should be injected through the initializer.
public protocol EventListener: Sendable {
    /// The event this listener handles.
    associatedtype EventType: Event

    /// The listener's dispatch priority. Higher values run first.
    static var priority: Int { get }

    /// Handles an event.
    ///
    /// - Parameter event: The event to handle.
    func handle(_ event: EventType) async throws
}

extension EventListener {
    /// The default priority.
    public static var priority: Int { 0 }
}
