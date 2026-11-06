import SwiftUI

/// Menu bar label. Placeholder until M3 shows the price (spec §6.1).
struct MenuBarView: View {
    var body: some View {
        #if DEBUG
        // shortcut: M0 label check only (roadmap M0); remove when M3 renders the real label.
        // `-MenuBarLabelPreview 11,111.11` shows the composite label with that price.
        if let preview = UserDefaults.standard.string(forKey: "MenuBarLabelPreview") {
            HStack(spacing: 4) {
                Image(systemName: "exclamationmark.triangle")
                Text("₿ \(preview)  +2.45%")
            }
            .monospacedDigit()
        } else {
            placeholder
        }
        #else
        placeholder
        #endif
    }

    private var placeholder: some View {
        Text("₿ —")
            .monospacedDigit()
            .accessibilityLabel("Bitcoin price, no data yet")
    }
}
