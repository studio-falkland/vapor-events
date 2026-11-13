import Vapor
import VaporEventsCore

extension Application {
    /// The application's broadcast configuration.
    public var broadcast: Broadcast {
        .init(application: self)
    }

    /// The storage key for the broadcast manager.
    struct BroadcastManagerKey: StorageKey, LockKey {
        typealias Value = BroadcastManager
    }

    /// The storage key marking the shutdown handler as registered.
    struct BroadcastShutdownKey: StorageKey {
        typealias Value = Bool
    }

    /// Installs the default broadcast manager for a dispatcher.
    ///
    /// - Parameter dispatcher: The dispatcher to observe.
    func ensureBroadcast(for dispatcher: any EventBus) {
        // Only an observing bus can be relayed.
        guard let observing = dispatcher as? (any EventBus & EventObserving) else { return }

        self.locks.lock(for: BroadcastManagerKey.self).withLock {
            // Create the default manager once.
            guard self.storage[BroadcastManagerKey.self] == nil else { return }

            // Create and start the manager.
            let manager = BroadcastManager(dispatcher: observing, logger: self.logger)
            self.storage[BroadcastManagerKey.self] = manager
            manager.start()

            // Register the shutdown handler once.
            if self.storage[BroadcastShutdownKey.self] == nil {
                self.storage[BroadcastShutdownKey.self] = true
                self.lifecycle.use(BroadcastShutdown())
            }
        }
    }

    /// Returns the current broadcast manager.
    func broadcastManager() -> BroadcastManager? {
        self.locks.lock(for: BroadcastManagerKey.self).withLock {
            self.storage[BroadcastManagerKey.self]
        }
    }

    /// Takes the current broadcast manager and clears the storage entry.
    func takeBroadcastManager() -> BroadcastManager? {
        self.locks.lock(for: BroadcastManagerKey.self).withLock {
            defer { self.storage[BroadcastManagerKey.self] = nil }
            return self.storage[BroadcastManagerKey.self]
        }
    }

    /// Stops and removes the current broadcast manager.
    func retireBroadcast() {
        guard let manager = self.takeBroadcastManager() else { return }
        Task { await manager.shutdown() }
    }
}
