/// Errors thrown by event test assertions.
///
/// These are thrown by ``FakeEventDispatcher``'s assertion helpers when an
/// expectation fails.
public enum EventAssertionError: Error, Sendable {
    /// No matching event was dispatched.
    case notDispatched(String)

    /// An event was dispatched when none was expected.
    case dispatched(String)

    /// The listener is not registered.
    case listenerNotRegistered(String)
}
