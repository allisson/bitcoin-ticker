import Testing
@testable import BitcoinTicker

/// Runs in both test plan configurations, so the signal is checked under each (spec §7).
struct TestHostTests {
    @Test func testHostIsDetected() {
        #expect(TestHost.isActive)
    }
}
