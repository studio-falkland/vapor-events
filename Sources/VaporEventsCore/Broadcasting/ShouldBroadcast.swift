/// Marks an event that should be published to other instances.
///
/// The ``BroadcastRelay`` publishes events that conform to this protocol and
/// subscribes to the same event types for remote delivery.
public protocol ShouldBroadcast: Event {}
