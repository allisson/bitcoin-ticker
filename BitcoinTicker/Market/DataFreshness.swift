/// Data freshness, separate from the connection state (spec §5.7).
enum DataFreshness: String, Sendable {
    case noData = "No data"
    case live = "Live"
    case stale = "Stale"

    /// Product heuristic, not a Binance guarantee; the only place to adjust it (spec §5.6).
    static let threshold: Duration = .seconds(30)
}
