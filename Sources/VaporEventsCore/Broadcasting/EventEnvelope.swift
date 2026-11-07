#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

/// A transport wrapper around a published event.
public struct EventEnvelope: Codable, Sendable {
    /// The unique identifier for this publication.
    public let id: UUID

    /// The event name.
    public let name: String

    /// The encoded event payload.
    public let payload: Data

    /// When the event was published.
    public let publishedAt: Date

    /// The identifier of the publishing dispatcher.
    public let origin: String

    /// Creates an envelope.
    ///
    /// - Parameters:
    ///   - id: The unique identifier for this publication.
    ///   - name: The event name.
    ///   - payload: The encoded event payload.
    ///   - publishedAt: When the event was published.
    ///   - origin: The identifier of the publishing dispatcher.
    public init(
        id: UUID = UUID(),
        name: String,
        payload: Data,
        publishedAt: Date = Date(),
        origin: String
    ) {
        self.id = id
        self.name = name
        self.payload = payload
        self.publishedAt = publishedAt
        self.origin = origin
    }
}
