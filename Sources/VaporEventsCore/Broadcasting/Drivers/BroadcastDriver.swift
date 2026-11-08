/// A live subscription to a broadcaster.
///
/// Obtain a subscription from ``BroadcastDriver/subscribe(to:)``. The stream
/// carries the envelopes received for one event type, and ``cancel()`` stops the
/// driver from delivering to it.
public struct EventSubscription<E: Event>: AsyncSequence, Sendable {
    public typealias Element = EventEnvelope<E>

    /// The envelopes received for the subscribed event type.
    public let stream: AsyncStream<EventEnvelope<E>>

    /// The cancellation that stops the subscription.
    package let cancellation: Cancellation

    /// Creates a subscription.
    ///
    /// - Parameters:
    ///   - stream: The stream of envelopes.
    ///   - cancel: A closure that stops the subscription.
    public init(
        stream: AsyncStream<EventEnvelope<E>>,
        cancel: @escaping @Sendable () -> Void
    ) {
        self.init(stream: stream, cancellation: Cancellation(cancel))
    }

    package init(
        stream: AsyncStream<EventEnvelope<E>>,
        cancellation: Cancellation
    ) {
        self.stream = stream
        self.cancellation = cancellation
    }

    /// Creates an iterator over the subscription.
    public func makeAsyncIterator() -> AsyncStream<EventEnvelope<E>>.AsyncIterator {
        self.stream.makeAsyncIterator()
    }

    /// Stops the subscription.
    public func cancel() {
        self.cancellation.cancel()
    }
}

/// A transport for publishing and receiving event envelopes.
///
/// Drivers are transport-specific: in-process, Postgres `LISTEN`/`NOTIFY`, or
/// Redis pub/sub. Each driver subscribes per event type and publishes
/// ``EventEnvelope`` values.
public protocol BroadcastDriver: Sendable {
    /// Publishes an envelope.
    ///
    /// - Parameter envelope: The envelope to publish.
    func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws

    /// Subscribes to envelopes of one event type.
    ///
    /// - Parameter type: The event type to subscribe to.
    /// - Returns: A cancellable subscription.
    func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E>

    /// Releases any resources held by the broadcaster.
    func shutdown() async
}
