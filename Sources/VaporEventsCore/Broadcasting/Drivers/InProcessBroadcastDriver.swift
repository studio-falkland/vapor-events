#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Synchronization

/// A ``BroadcastDriver`` that fans out envelopes within one process.
///
/// Useful for tests and single-instance deployments. It does not cross process
/// boundaries.
public final class InProcessBroadcastDriver: BroadcastDriver {
    /// Multicast channels keyed by event type.
    private let channels = Mutex<[ObjectIdentifier: any AnyMulticast]>([:])

    /// Creates an in-process broadcaster.
    public init() {}

    /// Publishes an envelope to every subscriber of its event type.
    ///
    /// - Parameter envelope: The envelope to publish.
    public func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws {
        // Deliver to the event type's channel, if anyone subscribed to it.
        self.channel(for: E.self)?.send(envelope)
    }

    /// Subscribes to envelopes of one event type.
    ///
    /// - Parameter type: The event type to subscribe to.
    /// - Returns: A cancellable subscription.
    public func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E> {
        // Create a channel for the event type and hand out a subscriber stream.
        let subscription = self.multicast(for: E.self).subscribe(bufferingPolicy: .bufferingNewest(64))

        return EventSubscription(stream: subscription.stream, cancellation: subscription.cancellation)
    }

    /// Finishes every subscriber stream.
    public func shutdown() async {
        // Take the channels, then finish them outside the lock.
        let all = self.channels.withLock { state in
            defer { state.removeAll() }
            return Array(state.values)
        }
        for channel in all {
            channel.finish()
        }
    }

    /// Returns the existing channel for an envelope type.
    private func channel<E: Event>(for type: E.Type) -> Multicast<EventEnvelope<E>>? {
        self.channels.withLock { state in
            state[ObjectIdentifier(E.self)] as? Multicast<EventEnvelope<E>>
        }
    }

    /// Returns the channel for an envelope type, creating it when needed.
    private func multicast<E: Event>(for type: E.Type) -> Multicast<EventEnvelope<E>> {
        let key = ObjectIdentifier(E.self)
        return self.channels.withLock { state in
            // Reuse the existing channel for the type.
            if let existing = state[key] as? Multicast<EventEnvelope<E>> {
                return existing
            }

            // Create and store a new channel.
            let channel = Multicast<EventEnvelope<E>>()
            state[key] = channel
            return channel
        }
    }
}
