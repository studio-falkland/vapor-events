import Testing
import VaporEvents

@Suite("VaporEvents")
struct VaporEventsTests {
    @Test
    func coreIsReExported() {
        #expect(VaporEventsCore.version == "0.1.0")
    }
}
