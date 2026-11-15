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
/// The driver uses one channel and one `LISTEN` connection for every event
/// type. Messages carry the event type name, so the driver can route them to
/// the matching subscribers. Payloads are JSON and capped at 8 KB.
public final class PostgresBroadcastDriver: BroadcastDriver {
    /// The maximum notification payload size.
    private static let maxPayloadSize = 8_000

    /// The longest delay between reconnects.
    private static let maxReconnectDelay = Duration.seconds(30)

    /// The delay before reconnecting after the listener ends cleanly.
    private static let resubscribeDelay = Duration.seconds(1)

    /// A transport message carrying the event type name.
    private struct BroadcastMessage<E: Event>: Codable, Sendable {
        let eventName: String
        let envelope: EventEnvelope<E>
    }

    /// The header used to route a message to its event type.
    private struct BroadcastHeader: Codable, Sendable {
        let eventName: String
    }

    /// A subscriber channel and the closure that delivers to it.
    private struct Registration: Sendable {
        /// The event type that owns the registration.
        let type: ObjectIdentifier

        /// The event type name, used for diagnostics.
        let typeName: String

        /// The channel fed by the listener.
        let channel: any AnyMulticast

        /// Decodes a message and delivers its envelope to the channel.
        let send: @Sendable (Data) -> Void
    }

    /// The state shared by concurrent calls.
    private struct State: Sendable {
        /// Registrations keyed by event name.
        var registrations: [String: Registration] = [:]

        /// The listener task, when running.
        var listener: Task<Void, Never>?

        /// Whether ``shutdown()`` has run.
        var isShuttingDown = false
    }

    /// The client used for publishing and listening.
    private let client: PostgresClient

    /// The task running a client the driver owns, if any.
    private let clientTask: Task<Void, Never>?

    /// The single `LISTEN`/`NOTIFY` channel.
    private let channel: String

    /// The logger used for transport failures.
    private let logger: Logger

    /// The shared state.
    private let state = Mutex(State())

    /// Creates a Postgres broadcaster.
    ///
    /// - Parameters:
    ///   - client: The client used for publishing and listening.
    ///   - channel: The `LISTEN`/`NOTIFY` channel used for every event type.
    ///   - logger: The logger used for transport failures.
    public init(
        client: PostgresClient,
        channel: String = "vapor_events",
        logger: Logger = Logger(label: "vapor-events.postgres")
    ) {
        self.client = client
        self.channel = Self.channelName(channel)
        self.logger = logger
        self.clientTask = nil
    }

    /// Creates a Postgres broadcaster that owns its client.
    ///
    /// The driver starts the client immediately and stops it in ``shutdown()``.
    ///
    /// - Parameters:
    ///   - configuration: The Postgres client configuration.
    ///   - channel: The `LISTEN`/`NOTIFY` channel used for every event type.
    ///   - logger: The logger used for transport failures.
    public init(
        configuration: PostgresClient.Configuration,
        channel: String = "vapor_events",
        logger: Logger = Logger(label: "vapor-events.postgres")
    ) {
        // Create the client and start it, so subscriptions can lease connections.
        let client = PostgresClient(
            configuration: configuration,
            backgroundLogger: logger
        )
        self.client = client
        self.channel = Self.channelName(channel)
        self.logger = logger
        self.clientTask = Task { await client.run() }
    }

    /// Publishes an envelope.
    ///
    /// - Parameter envelope: The envelope to publish.
    public func publish<E: Event>(_ envelope: EventEnvelope<E>) async throws {
        // Wrap the envelope with the event name so listeners can route it.
        let message = BroadcastMessage(eventName: E.name, envelope: envelope)
        let payload = try JSONEncoder().encode(message)
        guard payload.count <= Self.maxPayloadSize else {
            throw EventTransportError.payloadTooLarge(payload.count)
        }

        // Send the notification on the driver's single channel.
        self.logger.trace(
            "Publishing on Postgres",
            metadata: ["event": .string(E.name), "channel": .string(self.channel)]
        )
        let text = String(decoding: payload, as: UTF8.self)
        try await self.client.query(
            "SELECT pg_notify(\(self.channel), \(text))"
        )
    }

    /// Subscribes to envelopes of one event type.
    ///
    /// If another event type already uses the same ``Event/name``, the
    /// subscription is skipped and the returned stream is already finished.
    ///
    /// - Parameter type: The event type to subscribe to.
    /// - Returns: A cancellable subscription.
    public func subscribe<E: Event>(to type: E.Type) async -> EventSubscription<E> {
        self.logger.trace(
            "Subscribing on Postgres",
            metadata: ["event": .string(E.name), "channel": .string(self.channel)]
        )

        // Register the event type, starting the listener when needed.
        guard let channel = self.multicast(for: E.self) else {
            // Shut down or duplicate event name: return a finished stream.
            let (stream, continuation) = AsyncStream<EventEnvelope<E>>.makeStream()
            continuation.finish()
            return EventSubscription(stream: stream, cancel: {})
        }

        // Hand out a subscriber stream.
        let subscription = channel.subscribe(bufferingPolicy: .bufferingNewest(64))
        return EventSubscription(stream: subscription.stream, cancellation: subscription.cancellation)
    }

    /// Stops listening and cancels every subscription.
    public func shutdown() async {
        // Mark shutdown, take the listener, and take the registrations.
        let (listener, registrations) = self.state.withLock { state -> (Task<Void, Never>?, [Registration]) in
            state.isShuttingDown = true
            defer {
                state.listener = nil
                state.registrations.removeAll()
            }
            return (state.listener, Array(state.registrations.values))
        }

        // Cancel the listener and finish the subscriber channels outside the lock.
        self.logger.debug(
            "Shutting down Postgres driver",
            metadata: ["registrations": .stringConvertible(registrations.count)]
        )
        listener?.cancel()
        for registration in registrations {
            registration.channel.finish()
        }

        // Stop the client the driver owns, if any.
        self.clientTask?.cancel()
    }

    /// Returns the channel for an event type, registering it when needed.
    ///
    /// - Parameter type: The event type.
    /// - Returns: The channel, or `nil` when the driver is shut down or the
    ///   event name is already claimed by another type.
    private func multicast<E: Event>(for type: E.Type) -> Multicast<EventEnvelope<E>>? {
        let key = E.name
        return self.state.withLock { state in
            guard !state.isShuttingDown else { return nil }

            // Reuse the existing channel for the event type.
            if let existing = state.registrations[key] {
                guard existing.type == ObjectIdentifier(E.self) else {
                    self.logger.error(
                        "Skipping broadcast subscription for a duplicate event name",
                        metadata: [
                            "event": .string(key),
                            "existing": .string(existing.typeName),
                            "new": .string(String(reflecting: E.self)),
                        ]
                    )
                    return nil
                }
                return existing.channel as? Multicast<EventEnvelope<E>>
            }

            // Create the channel and its registration.
            let channel = Multicast<EventEnvelope<E>>()
            state.registrations[key] = Registration(
                type: ObjectIdentifier(E.self),
                typeName: String(reflecting: E.self),
                channel: channel,
                send: { data in
                    guard let message = try? JSONDecoder().decode(BroadcastMessage<E>.self, from: data) else {
                        return
                    }
                    channel.send(message.envelope)
                }
            )

            // Start the shared listener when the first event type is registered.
            if state.listener == nil {
                self.logger.debug("Starting Postgres listener", metadata: ["channel": .string(self.channel)])
                state.listener = self.listen()
            }

            return channel
        }
    }

    /// Listens for notifications on the single channel, reconnecting after failures.
    private func listen() -> Task<Void, Never> {
        let client = self.client
        let channelName = self.channel
        let logger = self.logger
        return Task { [weak self] in
            logger.debug("Postgres listener task started", metadata: ["channel": .string(channelName)])
            var delay = Duration.seconds(1)
            while !Task.isCancelled {
                do {
                    try await client.withConnection { connection in
                        try await connection.listen(on: channelName) { notifications in
                            for try await notification in notifications {
                                self?.route(Data(notification.payload.utf8))
                            }
                        }
                    }

                    // Reset the backoff and pause before reconnecting, so a
                    // cleanly closed connection does not spin the loop.
                    delay = .seconds(1)
                    try? await Task.sleep(for: Self.resubscribeDelay)
                } catch {
                    if Task.isCancelled { break }

                    // Log the failure and back off before reconnecting.
                    logger.warning("Postgres notification listener for \(channelName) failed: \(error)")
                    logger.debug("Reconnecting Postgres listener", metadata: ["channel": .string(channelName)])
                    try? await Task.sleep(for: delay)
                    delay = min(delay * 2, Self.maxReconnectDelay)
                }
            }
            logger.debug("Postgres listener task stopped", metadata: ["channel": .string(channelName)])
            self?.finishAll()
        }
    }

    /// Routes a received payload to its event type's subscribers.
    ///
    /// - Parameter data: The raw notification payload.
    private func route(_ data: Data) {
        // Decode the header to learn the event type.
        guard let header = try? JSONDecoder().decode(BroadcastHeader.self, from: data) else {
            self.logger.warning("Skipping a payload that is not a valid broadcast message.")
            return
        }
        self.logger.trace("Routing Postgres message", metadata: ["event": .string(header.eventName)])

        // Look up the registration and deliver the payload.
        let registration = self.state.withLock { $0.registrations[header.eventName] }
        guard let registration else {
            self.logger.debug("Skipping a payload for an unregistered event type: \(header.eventName)")
            return
        }
        registration.send(data)
    }

    /// Finishes every subscriber channel.
    private func finishAll() {
        let registrations = self.state.withLock { state -> [Registration] in
            defer { state.registrations.removeAll() }
            return Array(state.registrations.values)
        }
        for registration in registrations {
            registration.channel.finish()
        }
    }

    /// Sanitizes the channel name and keeps it within Postgres's 63-byte limit.
    ///
    /// - Parameter name: The requested channel name.
    /// - Returns: A valid `LISTEN`/`NOTIFY` channel name.
    private static func channelName(_ name: String) -> String {
        // Sanitize the name into a valid identifier.
        let sanitized = name.lowercased().map { character in
            character.isLetter || character.isNumber ? character : "_"
        }

        // Keep the channel name within Postgres's 63-byte limit.
        return String(sanitized.prefix(63))
    }
}
