import Vapor
import VaporEventsCore

extension Application {
    /// The application's event dispatcher.
    public var events: any EventBus {
        get {
            // Guard first access with the application lock.
            let dispatcher = self.locks.lock(for: EventDispatcherKey.self).withLock {
                // Reuse an existing dispatcher when present.
                if let existing = self.storage[EventDispatcherKey.self] {
                    return existing
                }

                // Create and store a dispatcher that enqueues queued listeners.
                let application = self
                let dispatcher = EventDispatcher(
                    enqueuing: QueueEnqueuing(application: { [weak application] in application })
                )
                self.storage[EventDispatcherKey.self] = dispatcher
                return dispatcher
            }

            // Install the default broadcaster and relay before listeners are added.
            self.ensureBroadcast(for: dispatcher)

            return dispatcher
        }
        set {
            // Replace the stored dispatcher.
            self.locks.lock(for: EventDispatcherKey.self).withLock {
                self.storage[EventDispatcherKey.self] = newValue
            }

            // Retire the broadcaster bound to the previous dispatcher.
            self.retireBroadcast()
        }
    }

    private struct EventDispatcherKey: StorageKey, LockKey {
        typealias Value = any EventBus
    }
}
