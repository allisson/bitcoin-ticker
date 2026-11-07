import SwiftUI

/// Menu bar label: `₿ 67,432.18  +2.45%`, with a status symbol in front while the data is Stale
/// (spec §6.1). It renders as a template, so it carries no color.
struct MenuBarView: View {
    let store: MarketDataStore<ContinuousClock>

    var body: some View {
        if let ticker = store.ticker {
            let formatter = PriceFormatter()
            let price = formatter.price(ticker.lastPrice)
            let change = formatter.change(ticker.priceChangePercent)
            let isStale = store.freshness == .stale
            HStack(spacing: 4) {
                if isStale {
                    Image(systemName: "exclamationmark.triangle")
                }
                Text("₿ \(price)  \(change)")
            }
            .monospacedDigit()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(isStale
                ? "Bitcoin price not current: \(price), 24-hour change \(change)"
                : "Bitcoin price \(price), 24-hour change \(change)")
        } else {
            Text("₿ —")
                .monospacedDigit()
                .accessibilityLabel("Bitcoin price, no data yet")
        }
    }
}
