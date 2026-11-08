import Queues
import VaporEventsCore

/// A job that runs a ``ShouldQueue`` listener.
///
/// The listener's ``EventListener/handle(_:)`` is the job body, so a queued
/// listener needs no separate `dequeue` implementation.
public struct ListenerJob<L: EventListener>: AsyncJob {
    /// The event type the listener handles.
    public typealias Payload = L.EventType

    /// The listener to run.
    public let listener: L

    /// Creates a job for a listener.
    ///
    /// - Parameter listener: The listener to run.
    public init(listener: L) {
        self.listener = listener
    }

    /// Runs the listener's handler.
    ///
    /// - Parameters:
    ///   - context: The queue context.
    ///   - payload: The event to handle.
    public func dequeue(_ context: QueueContext, _ payload: L.EventType) async throws {
        try await self.listener.handle(payload)
    }
}
