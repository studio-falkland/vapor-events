/// Observes event type registrations and dispatches.
///
/// Observers are infrastructure hooks, not listeners. They are notified of
/// every event type registration and every dispatch. The broadcast relay is one
/// observer.
package protocol DispatchObserver: AnyObject, Sendable {
    /// Called when an event type gets its first listener or stream.
    ///
    /// - Parameter type: The registered event type.
    func registered<E: Event>(_ type: E.Type) async

    /// Called when an event is dispatched.
    ///
    /// - Parameter event: The dispatched event.
    func dispatched<E: Event>(_ event: E) async
}
