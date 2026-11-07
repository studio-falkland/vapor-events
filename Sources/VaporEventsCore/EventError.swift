/// Errors thrown by the event system.
public enum EventError: Error, Sendable {
    /// A listener received an event of the wrong type.
    case typeMismatch(expected: String, actual: String)
}
