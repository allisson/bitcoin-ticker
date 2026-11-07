import SwiftUI

/// Popover: market summary, status, last update, and Quit (spec §6.2). M4 adds the two toggles.
struct PricePopoverView: View {
    let store: MarketDataStore<ContinuousClock>

    var body: some View {
        let formatter = PriceFormatter()
        let ticker = store.ticker
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text("BTC / USDT")
                    .font(.headline)
                Text("Binance Spot")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            HStack(alignment: .firstTextBaseline) {
                Text(ticker.map { formatter.price($0.lastPrice) } ?? "—")
                    .font(.title2.weight(.semibold))
                    .accessibilityLabel(ticker.map {
                        "\(store.freshness == .stale ? "Price not current:" : "Price") \(formatter.price($0.lastPrice))"
                    } ?? "Price, no data yet")
                Spacer()
                Text(ticker.map { formatter.change($0.priceChangePercent) } ?? "—")
                    .foregroundStyle(changeColor(ticker?.priceChangePercent))
                    .accessibilityLabel("24-hour change \(ticker.map { formatter.change($0.priceChangePercent) } ?? "no data yet")")
            }
            .monospacedDigit()

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                row("24h High", ticker.map { formatter.price($0.high) })
                row("24h Low", ticker.map { formatter.price($0.low) })
                row("24h Volume", ticker.map { formatter.volume($0.volume) })
            }
            .font(.callout)

            Divider()

            VStack(alignment: .leading, spacing: 4) {
                Text(StatusText.status(store.connectionState, store.freshness))
                    .fixedSize(horizontal: false, vertical: true) // wrap the longer statuses
                if let note = StatusText.note(store.freshness) {
                    Label(note, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
                // shortcut: re-evaluated only when the view re-renders; M4 re-evaluates on every popover open (spec §6.4).
                Text("Last update: \(store.lastUpdate.map { formatter.updateTime($0, now: Date()) } ?? "—")")
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .font(.callout)

            Divider()

            Button("Quit Bitcoin Ticker") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 260, alignment: .leading)
    }

    private func row(_ title: String, _ value: String?) -> some View {
        GridRow {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value ?? "—")
                .monospacedDigit()
                .gridColumnAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    /// Color only adds to the sign (spec §6.1, §6.5).
    private func changeColor(_ change: Decimal?) -> Color {
        guard let change else { return .primary }
        let formatted = PriceFormatter().change(change)
        if formatted.hasPrefix("+") { return .green }
        if formatted.hasPrefix("\u{2212}") { return .red }
        return .primary
    }
}
