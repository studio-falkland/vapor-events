import Vapor
import VaporEventsCore

extension Request {
    /// The application's event dispatcher.
    public var events: any EventBus {
        self.application.events
    }
}
