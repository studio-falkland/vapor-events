#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Synchronization

/// Fans one element out to every active subscriber.
///
/// Each subscriber receives its own `AsyncStream` with its own buffer, so a slow
/// subscriber cannot delay or drop elements for the others. Sending is
/// synchronous and lock-protected, so callers never suspend.
package final class Multicast<Element: Sendable>: Sendable {
    /// Subscriber buffers keyed by subscriber identifier.
    private let continuations = Mutex<[UUID: AsyncStream<Element>.Continuation]>([:])

    package init() {}

    /// A single subscriber's stream and its cancellation handle.
    package struct Subscription: Sendable {
        /// The elements delivered to this subscriber.
        package let stream: AsyncStream<Element>

        /// The cancellation that stops this subscriber.
        package let cancellation: Cancellation

        package init(stream: AsyncStream<Element>, cancellation: Cancellation) {
            self.stream = stream
            self.cancellation = cancellation
        }

        /// Stops this subscriber from receiving further elements.
        package func cancel() {
            self.cancellation.cancel()
        }
    }

    /// Creates a subscriber stream and its cancellation handle.
    ///
    /// - Parameter bufferingPolicy: How to buffer elements for this subscriber.
    /// - Returns: A subscription that receives every element sent while active.
    package func subscribe(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .bufferingNewest(64)
    ) -> Subscription {
        // Create the stream and a buffer that belongs to this subscriber alone.
        let (stream, continuation) = AsyncStream<Element>.makeStream(bufferingPolicy: bufferingPolicy)
        let id = UUID()

        // Register the subscriber and drop it when the consumer stops iterating.
        self.continuations.withLock { $0[id] = continuation }
        continuation.onTermination = { [weak self] _ in
            self?.continuations.withLock { $0[id] = nil }
        }

        return Subscription(
            stream: stream,
            cancellation: Cancellation {
                continuation.finish()
            }
        )
    }

    /// Delivers an element to every active subscriber.
    ///
    /// - Parameter element: The element to deliver.
    package func send(_ element: Element) {
        // Snapshot the subscribers, then yield outside the lock: yielding takes
        // the stream's internal lock while the termination handler takes ours.
        let targets = self.continuations.withLock { Array($0.values) }
        for continuation in targets {
            continuation.yield(element)
        }
    }

    /// Ends every subscriber stream.
    package func finish() {
        // Clear the registry before finishing, because finishing invokes the
        // termination handlers, which take the same lock.
        let targets = self.continuations.withLock { state in
            defer { state.removeAll() }
            return Array(state.values)
        }
        for continuation in targets {
            continuation.finish()
        }
    }
}

/// A type-erased ``Multicast`` that can be finished without knowing its element type.
package protocol AnyMulticast: Sendable {
    /// Ends every subscriber stream.
    func finish()
}

extension Multicast: AnyMulticast {}
