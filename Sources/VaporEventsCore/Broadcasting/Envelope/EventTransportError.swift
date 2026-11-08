/// Errors thrown by event transports.
///
/// ``payloadTooLarge(_:)`` is thrown when an encoded envelope exceeds the
/// transport's payload limit. ``invalidEnvelope`` is thrown when a received
/// payload cannot be decoded.
public enum EventTransportError: Error, Sendable {
    /// The encoded payload exceeds the transport limit.
    case payloadTooLarge(Int)

    /// The received payload is not a valid envelope.
    case invalidEnvelope
}
