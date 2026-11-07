/// A live stream of events.
public struct EventStream<E: Event>: AsyncSequence, Sendable {
    public typealias Element = E

    private let stream: AsyncStream<E>
    private let cancelStream: @Sendable () -> Void

    init(stream: AsyncStream<E>, cancel: @escaping @Sendable () -> Void) {
        self.stream = stream
        self.cancelStream = cancel
    }

    /// Creates an iterator over the stream.
    public func makeAsyncIterator() -> AsyncStream<E>.AsyncIterator {
        self.stream.makeAsyncIterator()
    }

    /// Stops the stream and removes its subscription.
    public func cancel() {
        self.cancelStream()
    }
}
