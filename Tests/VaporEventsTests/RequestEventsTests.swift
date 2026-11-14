import Testing
import Vapor
import VaporEvents

@Suite("Request.events")
struct RequestEventsTests {
    @Test
    func returnsApplicationDispatcher() async throws {
        // Create a testing application.
        let app = try await Application.make(.testing)
        defer { Task { try? await app.asyncShutdown() } }

        // Create a request.
        let request = Request(
            application: app,
            method: .GET,
            url: URI(string: "/"),
            on: app.eventLoopGroup.any()
        )

        // Verify the request uses the application's dispatcher.
        let requestDispatcher = try #require(request.events as? EventDispatcher)
        let appDispatcher = try #require(app.events as? EventDispatcher)
        #expect(requestDispatcher === appDispatcher)
    }
}
