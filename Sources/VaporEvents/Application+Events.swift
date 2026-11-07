import Vapor
import VaporEventsCore

extension Application {
    /// The application's event dispatcher.
    public var events: any EventDispatching {
        get {
            // Guard first access with the application lock.
            self.locks.lock(for: EventDispatcherKey.self).withLock {
                // Reuse an existing dispatcher when present.
                if let existing = self.storage[EventDispatcherKey.self] {
                    return existing
                }

                // Create and store the dispatcher.
                let dispatcher = EventDispatcher()
                self.storage[EventDispatcherKey.self] = dispatcher

                // Start and stop the dispatcher with the application.
                self.lifecycle.use(EventDispatcherLifecycle(dispatcher: dispatcher))
                return dispatcher
            }
        }
        set {
            // Replace the stored dispatcher.
            self.locks.lock(for: EventDispatcherKey.self).withLock {
                self.storage[EventDispatcherKey.self] = newValue
            }
        }
    }

    private struct EventDispatcherKey: StorageKey, LockKey {
        typealias Value = any EventDispatching
    }
}

private struct EventDispatcherLifecycle: LifecycleHandler {
    let dispatcher: any EventDispatching

    func didBootAsync(_ application: Application) async throws {
        await self.dispatcher.start()
    }

    func shutdownAsync(_ application: Application) async {
        await self.dispatcher.shutdown()
    }
}
