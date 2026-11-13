/// A named broadcast transport.
///
/// Connections identify registered drivers. The core provides ``default`` and
/// ``inProcess``; driver products add their own, and applications can define
/// custom connections with ``init(rawValue:)``.
public struct BroadcastConnection: RawRepresentable, Hashable, Sendable, CustomStringConvertible {
    /// The raw connection name.
    public let rawValue: String

    /// Creates a connection from a raw name.
    ///
    /// - Parameter rawValue: The connection name.
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The connection name.
    public var description: String {
        self.rawValue
    }

    /// The fallback connection for events that do not choose one.
    public static let `default` = Self(rawValue: "default")

    /// The built-in in-process transport.
    public static let inProcess = Self(rawValue: "inProcess")
}
