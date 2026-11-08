import Synchronization

/// A one-shot cancellation.
///
/// The handler runs at most once, when ``cancel()`` is called. Cancellation is
/// explicit: releasing the value does not cancel anything.
package final class Cancellation: Sendable {
    /// The handler to run, cleared once it has run.
    private let handler: Mutex<(@Sendable () -> Void)?>

    package init(_ handler: @escaping @Sendable () -> Void) {
        self.handler = Mutex(Optional(handler))
    }

    /// Runs the handler, unless it has already run.
    package func cancel() {
        // Take the handler so a second call is a no-op.
        let handler = self.handler.withLock { handler -> (@Sendable () -> Void)? in
            defer { handler = nil }
            return handler
        }
        handler?()
    }
}
