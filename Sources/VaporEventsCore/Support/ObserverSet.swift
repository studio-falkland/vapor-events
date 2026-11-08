import Synchronization

/// A mutable set of observers that hands out cancellations.
///
/// Observers are held strongly until their cancellation is invoked.
package final class ObserverSet<Observer: Sendable>: Sendable {
    /// The observers, keyed by identity.
    private let observers = Mutex<[ObjectIdentifier: Observer]>([:])

    package init() {}

    /// The observers at this moment.
    package var snapshot: [Observer] {
        self.observers.withLock { Array($0.values) }
    }

    /// Adds an observer under an identity.
    ///
    /// - Parameters:
    ///   - observer: The observer to add.
    ///   - id: The observer's identity, used to remove it.
    /// - Returns: A cancellation that removes the observer.
    package func add(_ observer: Observer, id: ObjectIdentifier) -> Cancellation {
        self.observers.withLock { $0[id] = observer }

        // Remove the observer when the cancellation runs.
        return Cancellation { [weak self] in
            self?.observers.withLock { $0[id] = nil }
        }
    }
}
