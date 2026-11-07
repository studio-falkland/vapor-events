/// Handles one event type.
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
