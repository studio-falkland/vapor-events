#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import PostgresNIO
import Synchronization
import VaporEventsCore

/// A ``BroadcastDriver`` backed by Postgres `LISTEN`/`NOTIFY`.
///
/// Each event type uses its own channel. Publishing sends `pg_notify`;
/// subscribing opens a dedicated `LISTEN` connection with a reconnect loop.
/// Payloads are JSON and capped at 8 KB.
public final class PostgresBroadcastDriver: BroadcastDriver {
    /// The maximum notification payload size.
    private static let maxPayloadSize = 8_000

    /// The longest delay between reconnects.
    private static let maxReconnectDelay = Duration.seconds(30)

    /// A subscriber channel and the task listening for it.
    private struct Registration: Sendable {
        /// The channel fed by the listener.
        let channel: any AnyMulticast

        /// The listener task.
        let task: Task<Void, Never>
    }

    /// The client used for publishing and listening.
    private let client: PostgresClient

    /// The channel prefix.
    private let channelPrefix: String

    /// The logger used for transport failures.
    private let logger: Logger

    /// Registrations keyed by event type.
    private let registrations = Mutex<[ObjectIdentifier: Registration]>([:])

    /// Creates a Postgres broadcaster.
    ///
    /// - Parameters:
    ///   - client: The client used for publishing and listening.
    ///   - channelPrefix: The prefix used to build per-event channel names.
    ///   - logger: The logger used for transport failures.
    public init(
        client: PostgresClient,
        channelPrefix: String = "vapor_events",
        logger: Logger = Logger(label: "vapor-events.postgres")
    ) {
        self.client = client
        self.channelPrefix = channelPrefix
        self.logger = logger
    }

    /// Publishes an envelope.
    ///
    /// - Parameter envelope: The envelope to publish.
    public func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws {
        // Encode the envelope and enforce the payload limit.
        let payload = try JSONEncoder().encode(envelope)
        guard payload.count <= Self.maxPayloadSize else {
            throw EventTransportError.payloadTooLarge(payload.count)
        }

        // Send the notification on the event's channel.
        let text = String(decoding: payload, as: UTF8.self)
        try await self.client.query(
            "SELECT pg_notify(\(self.channelName(for: E.name)), \(text))"
        )
    }

    /// Subscribes to envelopes of one event type.
    ///
    /// - Parameter type: The event type to subscribe to.
    /// - Returns: A cancellable subscription.
    public func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E> {
        // Reuse or create the channel and its listener for the event type.
        let channel = self.multicast(for: E.self)

        // Hand out a subscriber stream.
        let subscription = channel.subscribe(bufferingPolicy: .bufferingNewest(64))
        return EventSubscription(stream: subscription.stream, cancellation: subscription.cancellation)
    }

    /// Cancels every subscription.
    public func shutdown() async {
        // Take the registrations, then cancel them outside the lock.
        let all = self.registrations.withLock { state in
            defer { state.removeAll() }
            return Array(state.values)
        }
        for registration in all {
            registration.task.cancel()
            registration.channel.finish()
        }
    }

    /// Returns the channel for an event type, creating it and its listener when needed.
    private func multicast<E: Event>(for type: E.Type) -> Multicast<EventEnvelope<E>> {
        let key = ObjectIdentifier(E.self)
        return self.registrations.withLock { state in
            // Reuse the existing channel for the type.
            if let existing = state[key]?.channel as? Multicast<EventEnvelope<E>> {
                return existing
            }

            // Create the channel and start listening on the event's channel name.
            let channel = Multicast<EventEnvelope<E>>()
            let task = self.listen(on: self.channelName(for: E.name), deliveringTo: channel)
            state[key] = Registration(channel: channel, task: task)
            return channel
        }
    }

    /// Listens for notifications on a channel, reconnecting after failures.
    private func listen<E: Event>(
        on channelName: String,
        deliveringTo channel: Multicast<EventEnvelope<E>>
    ) -> Task<Void, Never> {
        let client = self.client
        let logger = self.logger
        return Task {
            var delay = Duration.seconds(1)
            while !Task.isCancelled {
                do {
                    try await client.withConnection { connection in
                        try await connection.listen(on: channelName) { notifications in
                            for try await notification in notifications {
                                // Skip payloads that are not valid envelopes.
                                let data = Data(notification.payload.utf8)
                                guard let envelope = try? JSONDecoder().decode(EventEnvelope<E>.self, from: data) else {
                                    logger.warning("Skipping a payload on \(channelName) that is not a valid envelope.")
                                    continue
                                }
                                channel.send(envelope)
                            }
                        }
                    }

                    // Reset the backoff after the connection closes cleanly.
                    delay = .seconds(1)
                } catch {
                    if Task.isCancelled { break }

                    // Log the failure and back off before reconnecting.
                    logger.warning("Postgres notification listener for \(channelName) failed: \(error)")
                    try? await Task.sleep(for: delay)
                    delay = min(delay * 2, Self.maxReconnectDelay)
                }
            }
            channel.finish()
        }
    }

    /// Builds a channel name for an event type.
    private func channelName(for eventName: String) -> String {
        // Sanitize the event name into a valid identifier.
        let sanitized = eventName.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "_"
        }
        let suffix = String(sanitized.suffix(48))

        // Keep the channel name within Postgres's 63-byte limit.
        return String("\(self.channelPrefix)_\(suffix)".prefix(63))
    }
}
