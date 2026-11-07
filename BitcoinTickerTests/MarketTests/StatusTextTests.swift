import Testing
@testable import BitcoinTicker

struct StatusTextTests {
    static let freshnesses: [DataFreshness] = [.noData, .live, .stale]

    /// Every row of the spec §6.2 table; states other than Connected read the same for any freshness.
    @Test(arguments: [
        (ConnectionState.connecting, "Connecting to Binance…"),
        (.reconnecting, "Reconnecting…"),
        (.rateLimited, "Binance is limiting connections from your network"),
        (.offline, "No internet connection"),
        (.unavailable, "Binance is not available from your network or region"),
    ])
    func statusIgnoresFreshnessOutsideConnected(state: ConnectionState, expected: String) {
        for freshness in Self.freshnesses {
            #expect(StatusText.status(state, freshness) == expected)
        }
    }

    @Test(arguments: [
        (DataFreshness.noData, "Connecting to Binance…"),
        (.live, "Live"),
        (.stale, "Waiting for data…"),
    ])
    func connectedStatusDependsOnFreshness(freshness: DataFreshness, expected: String) {
        #expect(StatusText.status(.connected, freshness) == expected)
    }

    @Test func staleNoteOnlyWhileStale() {
        #expect(StatusText.note(.stale) == "The price shown is not current")
        #expect(StatusText.note(.live) == nil)
        #expect(StatusText.note(.noData) == nil)
    }
}
