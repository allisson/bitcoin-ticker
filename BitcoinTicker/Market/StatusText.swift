/// The popover's status wording (spec §6.2), derived from connection state and data freshness.
enum StatusText {
    static func status(_ state: ConnectionState, _ freshness: DataFreshness) -> String {
        switch (state, freshness) {
        case (.connecting, _), (.connected, .noData): "Connecting to Binance…"
        case (.connected, .live): "Live"
        case (.connected, .stale): "Waiting for data…"
        case (.reconnecting, _): "Reconnecting…"
        case (.rateLimited, _): "Binance is limiting connections from your network"
        case (.offline, _): "No internet connection"
        case (.unavailable, _): "Binance is not available from your network or region"
        }
    }

    /// Shown in addition to the status while the data is Stale.
    static func note(_ freshness: DataFreshness) -> String? {
        freshness == .stale ? "The price shown is not current" : nil
    }
}
