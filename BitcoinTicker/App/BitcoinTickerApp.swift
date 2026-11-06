import SwiftUI

@main
struct BitcoinTickerApp: App {
    /// False in a unit-test host, so tests never show a menu bar item (spec §7).
    @State private var isMenuBarItemInserted: Bool

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
        // shortcut: the task keeps the client alive and drains its events; M2b moves this into MarketDataStore.
        let client = BinanceWebSocketClient(
            url: BinanceEndpoint.url, transport: URLSessionWebSocketTransport(),
            clock: ContinuousClock(), random: SystemRandomSource()
        )
        Task {
            await client.start()
            for await _ in client.events {}
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
