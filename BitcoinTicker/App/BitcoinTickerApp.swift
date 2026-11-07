import SwiftUI

@main
struct BitcoinTickerApp: App {
    /// False in a unit-test host, so tests never show a menu bar item (spec §7).
    @State private var isMenuBarItemInserted: Bool
    /// Created in every process but started only outside a unit-test host (spec §7).
    @State private var store: MarketDataStore<ContinuousClock>
    @State private var launchAtLogin = LaunchAtLogin()

    @MainActor
    init() {
        let clock = ContinuousClock()
        let client = BinanceWebSocketClient(
            url: BinanceEndpoint.url, transport: URLSessionWebSocketTransport(),
            clock: clock, random: SystemRandomSource()
        )
        let store = MarketDataStore(
            client: client, clock: clock, now: Date.init,
            pathSource: SystemNetworkPathSource(), wakeSource: SystemWakeSource()
        )
        _store = State(initialValue: store)
        if TestHost.isActive {
            _isMenuBarItemInserted = State(initialValue: false)
            return
        }
        // Runs before the scene exists, so a copy that quits never shows a second item.
        if SingleInstance.shouldQuitAtLaunch() {
            exit(0)
        }
        _isMenuBarItemInserted = State(initialValue: true)
        store.start()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { store.stop() }
        }
    }

    var body: some Scene {
        MenuBarExtra(isInserted: $isMenuBarItemInserted) {
            PricePopoverView(store: store, launchAtLogin: launchAtLogin)
        } label: {
            MenuBarView(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

enum TestHost {
    /// Set by XCTest in the process it hosts tests in, Swift Testing included.
    static let isActive = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
}
