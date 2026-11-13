#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import Synchronization
import Valkey
import VaporEventsCore

/// A ``BroadcastDriver`` backed by Valkey pub/sub.
///
/// Each event type uses its own channel. Publishing sends the JSON-encoded
/// envelope with `PUBLISH`; subscribing subscribes to the event's channel and
/// feeds received envelopes into a channel per event type. A subscription that
/// ends or fails is re-established with backoff.
///
/// The client owns its connections: one is held open by the subscription and the
/// rest serve `PUBLISH`, so `ValkeyClient` and `ValkeyClusterClient` both work.
/// The caller must run the client's background process for the driver's lifetime.
public final class ValkeyBroadcastDriver: BroadcastDriver {
    /// The longest delay between reconnects.
    private static let maxReconnectDelay = Duration.seconds(30)

    /// The delay before resubscribing after a subscription ends cleanly.
    private static let resubscribeDelay = Duration.seconds(1)

    /// A subscriber channel and its listener task.
    private struct Registration: Sendable {
        /// The channel fed by the listener.
        let channel: any AnyMulticast

        /// The listener task.
        let task: Task<Void, Never>
    }

    /// The state shared by concurrent calls.
    private struct State: Sendable {
        /// Registrations keyed by event type.
        var registrations: [ObjectIdentifier: Registration] = [:]

        /// Whether ``shutdown()`` has run.
        var isShuttingDown = false
    }

    /// The client used for publishing and subscribing.
    private let client: any ValkeyClientProtocol

    /// The channel prefix.
    private let channelPrefix: String

    /// The logger used for transport failures.
    private let logger: Logger

    /// The shared state.
    private let state = Mutex(State())

    /// Creates a Valkey broadcaster.
    ///
    /// - Parameters:
    ///   - client: The running client used for publishing and subscribing.
    ///   - channelPrefix: The prefix used to build per-event channel names.
    ///   - logger: The logger used for transport failures.
    public init(
        client: any ValkeyClientProtocol,
        channelPrefix: String = "vapor_events",
        logger: Logger = Logger(label: "vapor-events.valkey")
    ) {
        self.client = client
        self.channelPrefix = channelPrefix
        self.logger = logger
    }

    /// Publishes an envelope.
    ///
    /// - Parameter envelope: The envelope to publish.
    public func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws {
        // Encode the envelope as a string payload.
        let payload = try JSONEncoder().encode(envelope)
        let text = String(decoding: payload, as: UTF8.self)
        let channelName = self.channelName(for: E.name)
        self.logger.trace(
            "Publishing on Valkey",
            metadata: ["event": .string(E.name), "channel": .string(channelName)]
        )

        // Publish it on the event's channel.
        try await self.client.publish(
            channel: channelName,
            message: text
        )
    }

    /// Subscribes to envelopes of one event type.
    ///
    /// - Parameter type: The event type to subscribe to.
    /// - Returns: A cancellable subscription.
    public func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E> {
        self.logger.trace(
            "Subscribing on Valkey",
            metadata: ["event": .string(E.name), "channel": .string(self.channelName(for: E.name))]
        )

        // Hand out a subscription that ends at once when already shut down.
        guard let channel = self.multicast(for: E.self) else {
            let (stream, continuation) = AsyncStream<EventEnvelope<E>>.makeStream()
            continuation.finish()
            return EventSubscription(stream: stream, cancel: {})
        }

        // Hand out a subscriber stream.
        let subscription = channel.subscribe(bufferingPolicy: .bufferingNewest(64))
        return EventSubscription(stream: subscription.stream, cancellation: subscription.cancellation)
    }

    /// Cancels every subscription.
    public func shutdown() async {
        // Mark shutdown and take the registrations, acting on them outside the lock.
        let all = self.state.withLock { state -> [Registration] in
            state.isShuttingDown = true
            defer { state.registrations.removeAll() }
            return Array(state.registrations.values)
        }
        self.logger.debug(
            "Shutting down Valkey driver",
            metadata: ["registrations": .stringConvertible(all.count)]
        )
        for registration in all {
            // Cancelling the task unsubscribes, then ends its subscribers.
            registration.task.cancel()
            registration.channel.finish()
        }
    }

    /// Returns the channel for an event type, creating it and its listener when needed.
    ///
    /// - Parameter type: The event type.
    /// - Returns: The channel, or `nil` when the driver is shut down.
    private func multicast<E: Event>(for type: E.Type) -> Multicast<EventEnvelope<E>>? {
        let key = ObjectIdentifier(E.self)
        return self.state.withLock { state in
            guard !state.isShuttingDown else { return nil }

            // Reuse the existing channel for the type.
            if let existing = state.registrations[key]?.channel as? Multicast<EventEnvelope<E>> {
                return existing
            }

            // Create the channel and start listening on the event's channel name.
            let channel = Multicast<EventEnvelope<E>>()
            let channelName = self.channelName(for: E.name)
            self.logger.debug("Starting Valkey subscription", metadata: ["channel": .string(channelName)])
            let task = self.listen(on: channelName, deliveringTo: channel)
            state.registrations[key] = Registration(channel: channel, task: task)
            return channel
        }
    }

    /// Subscribes to a channel, resubscribing when the subscription ends.
    ///
    /// - Parameters:
    ///   - channelName: The Valkey channel to subscribe to.
    ///   - channel: The channel that receives the decoded envelopes.
    private func listen<E: Event>(
        on channelName: String,
        deliveringTo channel: Multicast<EventEnvelope<E>>
    ) -> Task<Void, Never> {
        let client = self.client
        let logger = self.logger
        return Task {
            logger.debug("Valkey subscription task started", metadata: ["channel": .string(channelName)])
            var delay = Duration.seconds(1)

            while !Task.isCancelled {
                do {
                    // Subscribe and decode every message into the channel. The call
                    // returns only when the subscription ends.
                    try await client.subscribe(to: [channelName]) { subscription in
                        for try await message in subscription {
                            // Skip payloads that are not valid envelopes.
                            let data = Data(String(message.message).utf8)
                            guard let envelope = try? JSONDecoder().decode(EventEnvelope<E>.self, from: data) else {
                                logger.warning("Skipping a payload on \(channelName) that is not a valid envelope.")
                                continue
                            }
                            logger.trace(
                                "Received Valkey message",
                                metadata: ["event": .string(E.name), "channel": .string(channelName)]
                            )
                            channel.send(envelope)
                        }
                    }

                    // A clean end means the subscription was dropped: back off briefly.
                    if Task.isCancelled { break }
                    delay = .seconds(1)
                    try? await Task.sleep(for: Self.resubscribeDelay)
                } catch {
                    if Task.isCancelled { break }

                    // Log the failure and back off before subscribing again.
                    logger.warning("Valkey subscription for \(channelName) failed: \(error)")
                    logger.debug("Reconnecting Valkey subscription", metadata: ["channel": .string(channelName)])
                    try? await Task.sleep(for: delay)
                    delay = min(delay * 2, Self.maxReconnectDelay)
                }
            }
            logger.debug("Valkey subscription task stopped", metadata: ["channel": .string(channelName)])
            channel.finish()
        }
    }

    /// Builds a channel name for an event type.
    private func channelName(for eventName: String) -> String {
        Self.channelName(prefix: self.channelPrefix, event: eventName)
    }

    /// Builds a channel name from a prefix and an event name.
    ///
    /// - Parameters:
    ///   - prefix: The channel prefix.
    ///   - event: The event type name.
    /// - Returns: The channel name, with the event name sanitized to `[a-z0-9_]`.
    static func channelName(prefix: String, event: String) -> String {
        // Sanitize the event name into a readable channel suffix.
        let sanitized = event.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "_"
        }

        // Join the prefix and the suffix; Valkey allows any bytes but readable
        // names make `PUBSUB CHANNELS` useful during debugging.
        return "\(prefix):\(String(sanitized))"
    }
}
