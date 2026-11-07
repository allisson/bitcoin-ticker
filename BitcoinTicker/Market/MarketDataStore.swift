import Foundation
import Network
import Observation
import os

/// Starts the client and turns its events into UI state: connection state, data freshness, the last
/// ticker, and the connection watchdog (spec §5.6, §5.7, §7).
@MainActor @Observable
final class MarketDataStore<C: Clock<Duration>> {
    private(set) var connectionState = ConnectionState.connecting
    private(set) var freshness = DataFreshness.noData
    private(set) var ticker: BinanceTickerMessage?
    /// Wall-clock time of the last valid ticker, for display only (spec §5.6).
    private(set) var lastUpdate: Date?

    private let client: BinanceWebSocketClient<C>
    private let clock: C
    private let now: () -> Date
    private let pathSource: any NetworkPathSource
    private let wakeSource: any WakeSource
    private let threshold: Duration
    private let logger = Logger(subsystem: Log.subsystem, category: "store")
    /// Wakes the deadline task when it waits with no deadline pending (spec §5.6).
    private let signals: AsyncStream<Void>
    private let signal: AsyncStream<Void>.Continuation

    @ObservationIgnored private var lastReceivedAt: C.Instant?
    /// When the state last became Connected; `nil` outside Connected and once the watchdog fired for it.
    @ObservationIgnored private var connectedAt: C.Instant?
    @ObservationIgnored private var isNetworkAvailable = true
    @ObservationIgnored private var isStarted = false
    @ObservationIgnored private var tasks: [Task<Void, Never>] = []

    init(
        client: BinanceWebSocketClient<C>, clock: C, now: @escaping () -> Date,
        pathSource: any NetworkPathSource, wakeSource: any WakeSource,
        threshold: Duration = DataFreshness.threshold
    ) {
        self.client = client
        self.clock = clock
        self.now = now
        self.pathSource = pathSource
        self.wakeSource = wakeSource
        self.threshold = threshold
        (signals, signal) = AsyncStream.makeStream(bufferingPolicy: .bufferingNewest(1))
    }

    /// The tasks hold the store until `stop()`.
    func start() {
        guard !isStarted else { return }
        isStarted = true
        let client = client
        tasks = [
            Task {
                await client.start()
                for await event in client.events { self.handle(event) }
            },
            Task {
                for await status in self.pathSource.statuses() { await self.pathChanged(status) }
            },
            Task {
                for await _ in self.wakeSource.wakes() {
                    self.logger.notice("Wake from sleep")
                    await client.reconnect()
                }
            },
            Task { await self.runDeadlines() },
        ]
    }

    /// Cancels the store's tasks and stops the client.
    func stop() {
        tasks.forEach { $0.cancel() }
        tasks = []
        signal.finish()
        let client = client
        Task { await client.stop() }
    }

    private func handle(_ event: ClientEvent) {
        switch event {
        case .state(let state):
            connectionState = state
            connectedAt = state == .connected ? clock.now : nil
            signal.yield()
        case .ticker(let message):
            ticker = message
            lastReceivedAt = clock.now
            lastUpdate = now()
            if freshness != .live {
                setFreshness(.live)
                signal.yield() // a freshness deadline appears
            }
        }
    }

    private func pathChanged(_ status: NWPath.Status) async {
        // `.requiresConnection` counts as available. Comparing with the last availability skips the
        // initial satisfied report and interface changes (spec §5.5).
        let available = status != .unsatisfied
        guard available != isNetworkAvailable else { return }
        isNetworkAvailable = available
        logger.notice("Network path \(available ? "available" : "unavailable", privacy: .public)")
        await client.setNetworkAvailable(available)
    }

    // MARK: Deadlines (spec §5.6)

    private var watchdogDeadline: C.Instant? {
        connectedAt.map { max($0, lastReceivedAt ?? $0).advanced(by: threshold) }
    }

    private var nextDeadline: C.Instant? {
        let freshnessDeadline = freshness == .live ? lastReceivedAt?.advanced(by: threshold) : nil
        return [freshnessDeadline, watchdogDeadline].compactMap { $0 }.min()
    }

    /// The single long-lived deadline task: sleeps until the earliest deadline, or waits for a signal
    /// when none is pending, and re-evaluates on every wake.
    private func runDeadlines() async {
        var signals = signals.makeAsyncIterator()
        while !Task.isCancelled {
            if evaluateDeadlines() {
                await client.reconnect()
            }
            if let deadline = nextDeadline {
                do { try await clock.sleep(until: deadline, tolerance: nil) } catch { return }
            } else if await signals.next() == nil {
                return
            }
        }
    }

    /// Applies the deadlines that have passed; returns whether the watchdog fired.
    private func evaluateDeadlines() -> Bool {
        let now = clock.now
        if freshness == .live, let lastReceivedAt, lastReceivedAt.advanced(by: threshold) <= now {
            setFreshness(.stale)
        }
        guard let watchdogDeadline, watchdogDeadline <= now else { return false }
        connectedAt = nil
        logger.notice("Watchdog: no valid ticker within the freshness threshold; reconnecting")
        return true
    }

    private func setFreshness(_ newFreshness: DataFreshness) {
        logger.notice("Data freshness: \(self.freshness.rawValue, privacy: .public) → \(newFreshness.rawValue, privacy: .public)")
        freshness = newFreshness
    }
}
