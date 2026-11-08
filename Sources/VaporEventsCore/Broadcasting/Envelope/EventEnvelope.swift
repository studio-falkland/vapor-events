#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A transport wrapper around a published event.
///
/// The envelope carries the event, a publication ID, a timestamp, and the
/// origin instance. The origin is used to suppress echoes on the publishing
/// instance.
public struct EventEnvelope<E: Event>: Codable, Sendable {
    /// The unique identifier for this publication.
    public let id: UUID

    /// The published event.
    public let event: E

    /// When the event was published.
    public let publishedAt: Date

    /// The identifier of the publishing dispatcher.
    public let origin: String

    /// Creates an envelope.
    ///
    /// - Parameters:
    ///   - id: The unique identifier for this publication.
    ///   - event: The published event.
    ///   - publishedAt: When the event was published.
    ///   - origin: The identifier of the publishing dispatcher.
    public init(
        id: UUID = UUID(),
        event: E,
        publishedAt: Date = Date(),
        origin: String
    ) {
        self.id = id
        self.event = event
        self.publishedAt = publishedAt
        self.origin = origin
    }
}
