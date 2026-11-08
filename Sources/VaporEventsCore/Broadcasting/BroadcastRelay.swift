#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Logging
import Synchronization

/// A subscription and its receiving task.
struct BroadcastSubscription: Sendable {
    /// Stops the subscription.
    let cancellation: Cancellation

    /// Consumes the subscription's stream.
    let task: Task<Void, Never>
}

/// Relays events between the local bus and a broadcast driver.
///
/// The relay observes an ``EventBus``. When a ``ShouldBroadcast`` event type is
/// registered, it subscribes to the driver for that type. When such an event is
/// dispatched, it publishes an ``EventEnvelope``. Received envelopes are fed
/// back into the bus, skipping the publishing instance's own envelopes.
package final class BroadcastRelay: DispatchObserver, Sendable {
    /// The state shared by concurrent calls.
    private struct State: Sendable {
        /// Active subscriptions keyed by event type.
        var subscriptions: [ObjectIdentifier: BroadcastSubscription] = [:]

        /// Event types with a subscription in flight.
        var subscribing: Set<ObjectIdentifier> = []

        /// The dispatcher observation, once started.
        var observation: Cancellation?

        /// Whether the system has started.
        var isStarted = false
    }

    /// The driver used for publishing and receiving.
    private let driver: any BroadcastDriver

    /// The dispatcher fed by received envelopes.
    private let dispatcher: any EventBus & EventObserving

    /// The identifier used to suppress echoes.
    private let instanceID: String

    /// The logger used for transport failures.
    private let logger: Logger

    /// The relay state.
    private let state = Mutex(State())

    /// Creates a broadcast relay.
    ///
    /// - Parameters:
    ///   - driver: The driver used for publishing and receiving.
    ///   - dispatcher: The dispatcher fed by received envelopes.
    ///   - instanceID: The identifier used to suppress echoes.
    ///   - logger: The logger used for transport failures.
    package init(
        driver: any BroadcastDriver,
        dispatcher: any EventBus & EventObserving,
        instanceID: String = UUID().uuidString,
        logger: Logger = Logger(label: "vapor-events")
    ) {
        self.driver = driver
        self.dispatcher = dispatcher
        self.instanceID = instanceID
        self.logger = logger
    }

    /// Starts observing the dispatcher.
    ///
    /// Register the relay before adding listeners, so that it observes every
    /// broadcast event type as it is registered.
    package func start() {
        // Start only once.
        let shouldStart = self.state.withLock { state -> Bool in
            guard !state.isStarted else { return false }
            state.isStarted = true
            return true
        }
        guard shouldStart else { return }

        // Register with the dispatcher and keep the cancellation.
        let observation = self.dispatcher.observe(self)

        // Store the observation, or drop it if shutdown ran in between.
        let stored = self.state.withLock { state -> Bool in
            guard state.isStarted else { return false }
            state.observation = observation
            return true
        }
        if !stored {
            observation.cancel()
        }
    }

    /// Stops observing and cancels subscriptions.
    package func shutdown() {
        // Take the subscriptions and the observation, and reset the state.
        let (subscriptions, observation) = self.state.withLock { state in
            defer {
                state.subscriptions.removeAll()
                state.subscribing.removeAll()
                state.observation = nil
                state.isStarted = false
            }
            return (Array(state.subscriptions.values), state.observation)
        }

        // Cancel outside the lock, because cancellation can re-enter the relay.
        observation?.cancel()
        for subscription in subscriptions {
            subscription.cancellation.cancel()
            subscription.task.cancel()
        }
    }

    /// Subscribes to a broadcast event type.
    ///
    /// - Parameter type: The registered event type.
    package func registered<E: Event>(_ type: E.Type) async {
        // Only broadcast events can arrive from another instance.
        guard E.self is any ShouldBroadcast.Type else { return }

        // Claim the type so concurrent registrations subscribe only once.
        let key = ObjectIdentifier(E.self)
        let shouldSubscribe = self.state.withLock { state -> Bool in
            guard state.isStarted else { return false }
            guard state.subscriptions[key] == nil else { return false }
            guard state.subscribing.insert(key).inserted else { return false }
            return true
        }
        guard shouldSubscribe else { return }

        // Subscribe and receive envelopes.
        let subscription = await self.driver.subscribe(to: E.self)
        let instanceID = self.instanceID
        let logger = self.logger
        let task = Task { [weak self] in
            for await envelope in subscription {
                // Ignore envelopes published by this instance.
                guard envelope.origin != instanceID else { continue }
                guard let self else { return }

                // Deliver the envelope to local listeners.
                do {
                    try await self.dispatcher.receive(envelope.event)
                } catch {
                    logger.warning("Failed to deliver a received broadcast event: \(error)")
                }
            }
        }

        // Store the subscription, or cancel it when shutdown won the race.
        let stored = self.state.withLock { state -> Bool in
            state.subscribing.remove(key)
            guard state.isStarted else { return false }
            state.subscriptions[key] = BroadcastSubscription(
                cancellation: subscription.cancellation,
                task: task
            )
            return true
        }
        if !stored {
            subscription.cancel()
            task.cancel()
        }
    }

    /// Publishes a broadcast event.
    ///
    /// - Parameter event: The dispatched event.
    package func dispatched<E: Event>(_ event: E) async {
        // Only broadcast events are published, and only after starting.
        guard E.self is any ShouldBroadcast.Type else { return }
        guard self.state.withLock({ $0.isStarted }) else { return }

        // Build and publish the envelope.
        let envelope = EventEnvelope(event: event, origin: self.instanceID)
        do {
            try await self.driver.publish(envelope)
        } catch {
            self.logger.warning("Failed to publish broadcast event \(E.name): \(error)")
        }
    }
}
