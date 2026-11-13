/// Marks an event that should be published to other instances.
///
/// The ``BroadcastRelay`` publishes events that conform to this protocol and
/// subscribes to the same event types for remote delivery.
public protocol ShouldBroadcast: Event {
    /// The connection used to broadcast this event type.
    ///
    /// Return `nil` to use the broadcaster's default connection.
    static var broadcastConnection: BroadcastConnection? { get }
}

extension ShouldBroadcast {
    /// The default connection.
    public static var broadcastConnection: BroadcastConnection? { nil }
}
