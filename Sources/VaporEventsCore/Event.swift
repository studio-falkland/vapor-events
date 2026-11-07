/// A value that can be dispatched through an ``EventDispatcher``.
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
