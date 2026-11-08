import Vapor
import VaporEventsCore

extension Application {
    /// The application's broadcast relay.
    public var broadcast: Broadcast {
        .init(application: self)
    }

    struct BroadcastRelayKey: StorageKey, LockKey {
        typealias Value = BroadcastRelay
    }
}
