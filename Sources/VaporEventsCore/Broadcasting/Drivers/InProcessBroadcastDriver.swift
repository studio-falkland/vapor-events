#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import Synchronization

/// A ``BroadcastDriver`` that fans out envelopes within one process.
///
/// Useful for tests and single-instance deployments. It does not cross process
/// boundaries.
public final class InProcessBroadcastDriver: BroadcastDriver {
    /// Multicast channels keyed by event type.
    private let channels = Mutex<[ObjectIdentifier: any AnyMulticast]>([:])

    /// The logger used for broadcast diagnostics.
    private let logger: Logger

    /// Creates an in-process broadcaster.
    ///
    /// - Parameter logger: The logger used for broadcast diagnostics.
    public init(logger: Logger = Logger(label: "vapor-events.in-process")) {
        self.logger = logger
    }

    /// Publishes an envelope to every subscriber of its event type.
    ///
    /// - Parameter envelope: The envelope to publish.
    public func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws {
        self.logger.trace("Publishing in process", metadata: ["event": .string(E.name)])

        // Deliver to the event type's channel, if anyone subscribed to it.
        self.channel(for: E.self)?.send(envelope)
    }

    /// Subscribes to envelopes of one event type.
    ///
    /// - Parameter type: The event type to subscribe to.
    /// - Returns: A cancellable subscription.
    public func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E> {
        self.logger.trace("Subscribing in process", metadata: ["event": .string(E.name)])

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
        self.logger.debug(
            "Shutting down in-process driver",
            metadata: ["channels": .stringConvertible(all.count)]
        )
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
