import Vapor
import VaporEventsCore

/// Stops broadcasting with the application lifecycle.
struct BroadcastShutdown: LifecycleHandler {
    /// The relay to stop.
    let relay: BroadcastRelay

    /// The driver to release.
    let driver: any BroadcastDriver

    func shutdownAsync(_ application: Application) async {
        // Stop observing and cancel subscriptions.
        self.relay.shutdown()

        // Release the driver's resources.
        await self.driver.shutdown()
    }
}
