/// A live subscription to a broadcaster.
public struct EventSubscription: Sendable {
    /// The stream of envelopes.
    public let stream: AsyncThrowingStream<EventEnvelope, any Error>

    private let cancelHandler: @Sendable () -> Void

    /// Creates a subscription.
    ///
    /// - Parameters:
    ///   - stream: The stream of envelopes.
    ///   - cancel: A closure that stops the subscription.
    public init(
        stream: AsyncThrowingStream<EventEnvelope, any Error>,
        cancel: @escaping @Sendable () -> Void
    ) {
        self.stream = stream
        self.cancelHandler = cancel
    }

    /// Stops the subscription.
    public func cancel() {
        self.cancelHandler()
    }
}

/// Publishes and receives event envelopes.
public protocol EventBroadcaster: Sendable {
    /// Publishes an envelope to other subscribers.
    ///
    /// - Parameter envelope: The envelope to publish.
    func publish(_ envelope: EventEnvelope) async throws

    /// Subscribes to published envelopes.
    ///
    /// - Returns: A cancellable subscription.
    func subscribe() async -> EventSubscription

    /// Releases any resources held by the broadcaster.
    func shutdown() async
}
