#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif
import Testing
import Vapor
@testable import VaporEvents

private let sharedConnection = BroadcastConnection(rawValue: "shared")

private struct SharedEvent: ShouldBroadcast {
    static var broadcastConnection: BroadcastConnection? { sharedConnection }
    let id: UUID
}

private struct LocalBroadcastEvent: ShouldBroadcast {
    let id: UUID
}

private actor BroadcastCounter {
    private(set) var count = 0

    func increment() {
        self.count += 1
    }
}

private struct SharedCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: SharedEvent) async throws {
        await self.counter.increment()
    }
}

private struct LocalCountingListener: EventListener {
    let counter: BroadcastCounter

    func handle(_ event: LocalBroadcastEvent) async throws {
        await self.counter.increment()
    }
}

private func waitUntil(
    timeout: Duration = .seconds(1),
    _ condition: @Sendable () async -> Bool
) async {
    // Poll until the condition holds or the deadline passes.
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if await condition() { return }
        try? await Task.sleep(for: .milliseconds(10))
    }
}

@Suite("Application.broadcast")
struct ApplicationBroadcastTests {
    @Test
    func defaultsToInProcess() async throws {
        // Create a testing application.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }

        // Register a listener and dispatch a broadcast event.
        let counter = BroadcastCounter()
        await app.events.listen(LocalCountingListener(counter: counter))
        try await app.events.dispatch(LocalBroadcastEvent(id: UUID()))

        // Give the relay a moment to process its own echo.
        try await Task.sleep(for: .milliseconds(50))

        // Verify the listener ran once.
        #expect(await counter.count == 1)
    }

    @Test
    func registeredConnectionBroadcastsBetweenApplications() async throws {
        // Create two applications sharing a driver.
        let driver = InProcessBroadcastDriver()
        let app1 = try await Application.make(.testing)
        let app2 = try await Application.make(.testing)
        defer {
            Task { try? await app1.asyncShutdown() }
            Task { try? await app2.asyncShutdown() }
        }

        // Register the shared connection on both applications.
        app1.broadcast.register(sharedConnection, driver)
        app2.broadcast.register(sharedConnection, driver)

        // Register a listener on the second application.
        let counter = BroadcastCounter()
        await app2.events.listen(SharedCountingListener(counter: counter))

        // Dispatch from the first application.
        try await app1.events.dispatch(SharedEvent(id: UUID()))

        // Wait for the second application's listener.
        await waitUntil { await counter.count == 1 }
        #expect(await counter.count == 1)
    }

    @Test
    func useReturnsSelfForChaining() async throws {
        // Create a testing application.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }

        // Chain registration and default selection.
        let connection = BroadcastConnection(rawValue: "test")
        let result = app.broadcast
            .register(connection, InProcessBroadcastDriver())
            .useDefault(connection)

        // Verify the facade returned itself.
        #expect(result.application === app)
    }
}
