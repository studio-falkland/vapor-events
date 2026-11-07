#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// Broadcasting state for a dispatcher.
struct BroadcastState: Sendable {
    /// The broadcaster used for published events.
    let broadcaster: any EventBroadcaster

    /// The identifier used to suppress echoes.
    let instanceID: String

    /// The active broadcaster subscription.
    var subscription: EventSubscription?

    /// The task receiving envelopes.
    var task: Task<Void, Never>?

    /// Whether a subscription is being established.
    var isStarting = false
}

extension EventDispatcher {
    /// Publishes a broadcast event.
    ///
    /// - Parameter event: The event to publish.
    func publish<E: Event>(_ event: E) async throws {
        // Encode the event payload.
        let payload = try JSONEncoder().encode(event)

        // Build and publish the envelope.
        let envelope = EventEnvelope(
            name: E.name,
            payload: payload,
            origin: self.broadcast.instanceID
        )
        try await self.broadcast.broadcaster.publish(envelope)
    }

    /// Receives an envelope from the broadcaster.
    ///
    /// - Parameter envelope: The envelope to receive.
    public func receive(_ envelope: EventEnvelope) async throws {
        // Ignore envelopes published by this dispatcher.
        guard envelope.origin != self.broadcast.instanceID else { return }

        // Decode the event payload.
        guard let decoder = self.decoders[envelope.name] else { return }
        let event = try decoder(envelope.payload)

        // Run listeners for the event.
        let registrations = self.registrations[envelope.name] ?? []
        for registration in registrations {
            try await registration.handle(event)
        }

        // Feed live streams after listeners.
        let streams = self.streams[envelope.name] ?? []
        for stream in streams {
            stream.yield(event)
        }
    }

    /// Starts receiving broadcast events.
    public func start() async {
        // Avoid starting more than once.
        guard self.broadcast.subscription == nil, !self.broadcast.isStarting else { return }
        self.broadcast.isStarting = true

        // Subscribe before returning so no events are missed.
        let broadcaster = self.broadcast.broadcaster
        let subscription = await broadcaster.subscribe()
        self.broadcast.isStarting = false
        self.broadcast.subscription = subscription

        // Receive envelopes in the background.
        self.broadcast.task = Task { [weak self] in
            do {
                for try await envelope in subscription.stream {
                    guard let self else { return }
                    do {
                        try await self.receive(envelope)
                    } catch {
                        // Ignore receive errors for now.
                    }
                }
            } catch {
                // Ignore stream errors for now.
            }
        }
    }

    /// Stops receiving broadcast events.
    public func shutdown() async {
        // Cancel the subscription and its task.
        self.broadcast.subscription?.cancel()
        self.broadcast.subscription = nil
        self.broadcast.task?.cancel()
        self.broadcast.task = nil
        self.broadcast.isStarting = false
    }
}
