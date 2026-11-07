#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Fans out envelopes within one process.
public actor InProcessBroadcaster: EventBroadcaster {
    /// Active subscriber continuations keyed by identifier.
    private var continuations: [UUID: AsyncThrowingStream<EventEnvelope, any Error>.Continuation] = [:]

    /// Creates an in-process broadcaster.
    public init() {}

    /// Publishes an envelope to every subscriber.
    ///
    /// - Parameter envelope: The envelope to publish.
    public func publish(_ envelope: EventEnvelope) async throws {
        // Yield the envelope to each subscriber.
        for continuation in self.continuations.values {
            continuation.yield(envelope)
        }
    }

    /// Subscribes to published envelopes.
    ///
    /// - Returns: A cancellable subscription.
    public func subscribe() -> EventSubscription {
        // Create the stream and its continuation.
        let id = UUID()
        let (stream, continuation) = AsyncThrowingStream<EventEnvelope, any Error>.makeStream()

        // Register the continuation.
        self.continuations[id] = continuation

        // Remove the continuation when the stream terminates.
        continuation.onTermination = { [weak self] _ in
            guard let self else { return }
            Task { await self.remove(id) }
        }

        // Return a cancellable subscription.
        return EventSubscription(stream: stream) {
            continuation.finish()
        }
    }

    /// Finishes every subscriber stream.
    public func shutdown() async {
        // Finish and drop every continuation.
        for continuation in self.continuations.values {
            continuation.finish()
        }
        self.continuations.removeAll()
    }

    /// Removes a subscriber continuation.
    private func remove(_ id: UUID) {
        self.continuations[id] = nil
    }
}
