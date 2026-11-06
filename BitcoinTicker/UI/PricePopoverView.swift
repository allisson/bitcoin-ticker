import SwiftUI

/// Popover. Placeholder until M3 adds the market summary (spec §6.2).
struct PricePopoverView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("BTC / USDT")
                .font(.headline)
            Text("Binance Spot")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("—")
                .font(.title2)
                .monospacedDigit()
            Divider()
            Button("Quit Bitcoin Ticker") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .padding()
        .frame(width: 240, alignment: .leading)
    }
}
