import Vapor
import VaporEventsCore

extension Request {
    /// The application's event dispatcher.
    public var events: any EventDispatching {
        self.application.events
    }
}
