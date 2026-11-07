import SwiftUI

@main
struct BitcoinTickerApp: App {
    /// False in a unit-test host, so tests never show a menu bar item (spec §7).
    @State private var isMenuBarItemInserted: Bool
    /// `nil` in a unit-test host (spec §7). M3 passes it to the views.
    @State private var store: MarketDataStore<ContinuousClock>?

    @MainActor
    init() {
        if TestHost.isActive {
            _isMenuBarItemInserted = State(initialValue: false)
            return
        }
        // Runs before the scene exists, so a copy that quits never shows a second item.
        if SingleInstance.shouldQuitAtLaunch() {
            exit(0)
        }
        _isMenuBarItemInserted = State(initialValue: true)
        let clock = ContinuousClock()
        let client = BinanceWebSocketClient(
            url: BinanceEndpoint.url, transport: URLSessionWebSocketTransport(),
            clock: clock, random: SystemRandomSource()
        )
        let store = MarketDataStore(
            client: client, clock: clock, now: Date.init,
            pathSource: SystemNetworkPathSource(), wakeSource: SystemWakeSource()
        )
        store.start()
        _store = State(initialValue: store)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { store.stop() }
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $isMenuBarItemInserted) {
            PricePopoverView()
        } label: {
            MenuBarView()
        }
        .menuBarExtraStyle(.window)
    }
}

enum TestHost {
    /// Set by XCTest in the process it hosts tests in, Swift Testing included.
    static let isActive = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
