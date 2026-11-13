import Vapor

/// Stops broadcasting with the application lifecycle.
struct BroadcastShutdown: LifecycleHandler {
    func shutdownAsync(_ application: Application) async {
        // Take the manager and clear the storage entry.
        guard let manager = application.takeBroadcastManager() else { return }
        application.logger.debug("Shutting down broadcast manager with the application")

        // Stop observing and release the drivers.
        await manager.shutdown()
    }
}
