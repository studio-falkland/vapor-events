/// A value that can be dispatched through an ``EventBus``.
///
/// Events are immutable, `Codable` value types. The default ``name`` is the
/// fully qualified type name, used for registration, transport channels, and
/// decoding.
public protocol Event: Codable, Sendable {
    /// The stable name used for registration and transport.
    static var name: String { get }
}

extension Event {
    /// The fully qualified type name.
    public static var name: String {
        String(reflecting: Self.self)
    }
}
