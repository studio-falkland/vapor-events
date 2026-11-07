import Vapor
import VaporEventsCore

extension Application {
    /// The application's event dispatcher.
    public var events: EventDispatcher {
        // Guard first access with the application lock.
        self.locks.lock(for: EventDispatcherKey.self).withLock {
            // Reuse an existing dispatcher when present.
            if let existing = self.storage[EventDispatcherKey.self] {
                return existing
            }

            // Create and store the dispatcher.
            let dispatcher = EventDispatcher()
            self.storage[EventDispatcherKey.self] = dispatcher
            return dispatcher
        }
    }

    private struct EventDispatcherKey: StorageKey, LockKey {
        typealias Value = EventDispatcher
    }
}
