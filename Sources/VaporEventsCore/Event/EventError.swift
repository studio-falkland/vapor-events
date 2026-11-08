/// Errors thrown by the event system.
///
/// A ``typeMismatch(expected:actual:)`` indicates that a registration received
/// an event of a different type, usually because two event types share an
/// ``Event/name``.
public enum EventError: Error, Sendable {
    /// A listener received an event of the wrong type.
    case typeMismatch(expected: String, actual: String)
}
