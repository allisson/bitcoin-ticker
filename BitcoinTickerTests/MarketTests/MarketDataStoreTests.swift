import Foundation
import Network
import Testing
@testable import BitcoinTicker

/// The store over the real client, with the fake transport, manual clock, and fake path and wake
/// sources. As with `ClientHarness`, wait for a sleeper or a state before advancing the clock.
@MainActor
struct StoreHarness {
    let clock: ManualClock
    let transport: FakeWebSocketTransport
    let path = FakeNetworkPathSource()
    let wake = FakeWakeSource()
    let store: MarketDataStore<ManualClock>
    private let connections: StreamRecorder<FakeWebSocketConnection>

    init(_ configuration: ClientConfiguration = ClientConfiguration()) {
        let clock = ManualClock()
        let transport = FakeWebSocketTransport(clock: clock)
        let client = BinanceWebSocketClient(
            url: ClientHarness.url, transport: transport, clock: clock,
            random: FixedRandomSource(value: 1), configuration: configuration
        )
        self.clock = clock
        self.transport = transport
        store = MarketDataStore(
            client: client, clock: clock, now: { Self.date(clock.now.offset) },
            pathSource: path, wakeSource: wake
        )
        connections = StreamRecorder(transport.connections)
    }

    /// The fake wall clock: the manual clock's offset as seconds since 1970.
    nonisolated static func date(_ offset: Duration) -> Date {
        Date(timeIntervalSince1970: Double(offset.components.seconds))
    }

    /// A configuration whose backoff delays last 600 s, longer than any freshness deadline.
    static let longBackoff: ClientConfiguration = {
        var configuration = ClientConfiguration()
        configuration.backoffBase = .seconds(600)
        configuration.backoffCap = .seconds(600)
        return configuration
    }()

    var connectionCount: Int { transport.all.count }

    func nextConnection() async throws -> FakeWebSocketConnection {
        try #require(await connections.next())
    }

    /// Completes the handshake and waits until the store shows Connected.
    func open(_ connection: FakeWebSocketConnection) async {
        connection.send(.opened)
        #expect(await reaches(.connected))
    }

    /// Sends a valid ticker and waits until the store shows its price.
    func sendTicker(_ connection: FakeWebSocketConnection, price: String) async {
        connection.send(ClientHarness.ticker(price: price))
        #expect(await eventually { store.ticker?.lastPrice == Decimal(string: price) })
    }

    func reaches(_ state: ConnectionState) async -> Bool {
        await eventually { store.connectionState == state }
    }

    func reaches(_ freshness: DataFreshness) async -> Bool {
        await eventually { store.freshness == freshness }
    }

    func hasSleeper(at seconds: Double) async -> Bool {
        await eventually { clock.deadlines.contains(.seconds(seconds)) }
    }

    func advance(to seconds: Double) {
        clock.advance(to: .seconds(seconds))
    }
}

@MainActor
struct MarketDataStoreTests {
    // MARK: Freshness

    @Test func liveTurnsStaleWithoutFurtherMessages() async throws {
        let h = StoreHarness()
        h.store.start()
        #expect(h.store.freshness == .noData)
        let connection = try await h.nextConnection()
        await h.open(connection)
        #expect(await h.hasSleeper(at: 30))
        h.advance(to: 10)
        await h.sendTicker(connection, price: "100")
        #expect(h.store.freshness == .live)
        #expect(h.store.lastUpdate == StoreHarness.date(.seconds(10)))

        h.advance(to: 30)
        #expect(await h.hasSleeper(at: 40))
        #expect(h.store.freshness == .live)
        h.advance(to: 40)
        #expect(await h.reaches(DataFreshness.stale))
        #expect(h.store.ticker?.lastPrice == 100) // the last known value is kept
    }

    @Test func clockJumpStandingInForSleepMakesDataStale() async throws {
        let h = StoreHarness()
        h.store.start()
        let connection = try await h.nextConnection()
        await h.open(connection)
        await h.sendTicker(connection, price: "100")
        #expect(await h.hasSleeper(at: 30))
        h.clock.advance(by: .seconds(8 * 60 * 60))
        #expect(await h.reaches(DataFreshness.stale))
    }

    @Test func priceStaysLiveThroughTheDailyCloseAndAQuickReconnect() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        await h.sendTicker(first, price: "1")
        h.advance(to: 20)
        await h.sendTicker(first, price: "2")
        h.advance(to: 30)
        await h.sendTicker(first, price: "3") // stable: k back to 1

        first.send(.closed)
        #expect(await h.reaches(.reconnecting))
        #expect(h.store.freshness == .live)
        #expect(await h.hasSleeper(at: 31)) // k = 1 backoff
        h.advance(to: 31)
        let second = try await h.nextConnection()
        await h.open(second)
        await h.sendTicker(second, price: "4")
        #expect(h.store.freshness == .live)
    }

    // MARK: Watchdog

    @Test func watchdogReconnectsOnceASilentConnectionWithoutChangingK() async throws {
        let h = StoreHarness(ClientHarness.noMinimumInterval)
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        await h.sendTicker(first, price: "1")
        h.advance(to: 10)
        await h.sendTicker(first, price: "2")
        h.advance(to: 30)
        #expect(await h.hasSleeper(at: 40)) // measured from the last valid ticker
        #expect(h.connectionCount == 1)

        h.advance(to: 40)
        let second = try await h.nextConnection()
        #expect(first.isClosed)
        // A failure now waits the k = 1 backoff (1 s), so the watchdog reconnect left k at 1.
        second.send(.handshakeFailed(status: 500, retryAfter: nil))
        #expect(await h.hasSleeper(at: 41))
        await settle()
        #expect(h.connectionCount == 2)
    }

    @Test func watchdogMeasuresFromTheHandshakeAfterALongOutage() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        await h.sendTicker(first, price: "1")
        h.path.send(.unsatisfied)
        #expect(await h.reaches(.offline))
        #expect(await h.hasSleeper(at: 30))
        h.advance(to: 30)
        #expect(await h.reaches(DataFreshness.stale))

        h.advance(to: 3600)
        h.path.send(.satisfied)
        let second = try await h.nextConnection()
        #expect(await h.reaches(.reconnecting))
        await h.open(second)
        #expect(await h.hasSleeper(at: 3630))
        h.advance(to: 3629)
        await settle()
        #expect(h.connectionCount == 2) // no reconnect right after the handshake

        h.advance(to: 3630) // the new connection never sent data
        _ = try await h.nextConnection()
        #expect(first.isClosed && second.isClosed)
    }

    @Test func firstHandshakeSinceLaunchFollowedBySilenceGetsOneWatchdogReconnect() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await settle() // the deadline task waits for a signal: nothing is pending
        await h.open(first)
        #expect(await h.hasSleeper(at: 30))
        h.advance(to: 30)
        _ = try await h.nextConnection()
        await settle()
        #expect(h.connectionCount == 2)
    }

    @Test func handshakeAfterStaleDataFollowedBySilenceGetsOneWatchdogReconnect() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        await h.sendTicker(first, price: "1")
        h.path.send(.unsatisfied)
        #expect(await h.reaches(.offline))
        #expect(await h.hasSleeper(at: 30))
        h.advance(to: 30)
        #expect(await h.reaches(DataFreshness.stale))
        await settle() // the deadline task waits for a signal: nothing is pending

        h.path.send(.satisfied)
        let second = try await h.nextConnection()
        #expect(await h.reaches(.reconnecting))
        await h.open(second)
        #expect(await h.hasSleeper(at: 60))
        h.advance(to: 60)
        _ = try await h.nextConnection()
        await settle()
        #expect(h.connectionCount == 3)
    }

    @Test func noWatchdogReconnectWhileConnectingDuringBackoff() async throws {
        let h = StoreHarness(StoreHarness.longBackoff)
        h.store.start()
        let first = try await h.nextConnection()
        first.send(.handshakeFailed(status: 500, retryAfter: nil))
        #expect(await h.hasSleeper(at: 600))
        h.advance(to: 120)
        await settle()
        #expect(h.connectionCount == 1)
        #expect(h.store.connectionState == .connecting)
    }

    @Test func noWatchdogReconnectWhileReconnectingDuringBackoff() async throws {
        let h = StoreHarness(StoreHarness.longBackoff)
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        await h.sendTicker(first, price: "1")
        first.send(.closed)
        #expect(await h.reaches(.reconnecting))
        #expect(await h.hasSleeper(at: 600))
        #expect(await h.hasSleeper(at: 30))
        h.advance(to: 30)
        #expect(await h.reaches(DataFreshness.stale))
        h.advance(to: 120)
        await settle()
        #expect(h.connectionCount == 1)
        #expect(h.store.connectionState == .reconnecting)
    }

    @Test(arguments: [(429, ConnectionState.rateLimited), (451, ConnectionState.unavailable)])
    func noWatchdogReconnectDuringAFixedDelay(status: Int, state: ConnectionState) async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        await h.sendTicker(first, price: "1")
        first.send(.closed)
        #expect(await h.hasSleeper(at: 2)) // minimum attempt interval
        h.advance(to: 2)
        let second = try await h.nextConnection()
        second.send(.handshakeFailed(status: status, retryAfter: nil))
        #expect(await h.reaches(state))
        #expect(await h.hasSleeper(at: 62))
        h.advance(to: 30)
        #expect(await h.reaches(DataFreshness.stale))
        h.advance(to: 61)
        await settle()
        #expect(h.connectionCount == 2)
        h.advance(to: 62)
        _ = try await h.nextConnection()
    }

    @Test func noWatchdogReconnectWhileOffline() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        await h.sendTicker(first, price: "1")
        h.path.send(.unsatisfied)
        #expect(await h.reaches(.offline))
        #expect(await h.hasSleeper(at: 30))
        h.advance(to: 30)
        #expect(await h.reaches(DataFreshness.stale))
        h.advance(to: 600)
        await settle()
        #expect(h.connectionCount == 1)
        #expect(h.store.connectionState == .offline)
    }

    // MARK: Path and wake

    @Test func pathReturnAndWakeDoNotShortenAFixedDelay() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        first.send(.handshakeFailed(status: 451, retryAfter: nil))
        #expect(await h.reaches(.unavailable))
        h.path.send(.unsatisfied)
        #expect(await h.reaches(.offline))
        h.advance(to: 10)
        h.path.send(.satisfied)
        #expect(await h.reaches(.unavailable))
        h.wake.wake()
        await settle()
        h.advance(to: 59)
        await settle()
        #expect(h.connectionCount == 1)
        #expect(await h.hasSleeper(at: 60))
        h.advance(to: 60)
        _ = try await h.nextConnection()
    }

    @Test func initialSatisfiedPathAndInterfaceChangesDoNotReconnect() async throws {
        let h = StoreHarness()
        h.store.start()
        h.path.send(.satisfied)
        let first = try await h.nextConnection()
        await h.open(first)
        h.path.send(.satisfied) // for example, Wi-Fi to Ethernet
        h.path.send(.satisfied)
        await settle()
        #expect(h.connectionCount == 1)
        #expect(!first.isClosed)
        #expect(h.store.connectionState == .connected)
    }

    @Test func initialUnsatisfiedPathGivesOffline() async throws {
        let h = StoreHarness()
        h.path.send(.unsatisfied)
        h.store.start()
        #expect(await h.reaches(.offline))
        await settle()
        let open = h.transport.all.filter { !$0.isClosed }
        #expect(open.isEmpty)
    }

    @Test func pathLossGivesOffline() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        h.path.send(.unsatisfied)
        #expect(await h.reaches(.offline))
        #expect(first.isClosed)
    }

    @Test func requiresConnectionPathCountsAsAvailable() async throws {
        let h = StoreHarness()
        h.path.send(.requiresConnection)
        h.store.start()
        let first = try await h.nextConnection()
        await settle()
        #expect(h.store.connectionState == .connecting)
        #expect(!first.isClosed)
        await h.open(first)
    }

    @Test func wakeWhileConnectedReconnects() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        h.wake.wake()
        #expect(await h.reaches(.reconnecting))
        #expect(first.isClosed)
        #expect(await h.hasSleeper(at: 2)) // minimum attempt interval
        h.advance(to: 2)
        _ = try await h.nextConnection()
    }

    @Test func wakeWhileOfflineStartsNoAttempt() async throws {
        let h = StoreHarness()
        h.store.start()
        _ = try await h.nextConnection()
        h.path.send(.unsatisfied)
        #expect(await h.reaches(.offline))
        h.wake.wake()
        await settle()
        h.advance(to: 600)
        await settle()
        #expect(h.connectionCount == 1)
        #expect(h.store.connectionState == .offline)
    }

    // MARK: Shutdown

    @Test func stopCancelsTheDeadlineTaskAndTheClient() async throws {
        let h = StoreHarness()
        h.store.start()
        let first = try await h.nextConnection()
        await h.open(first)
        await h.sendTicker(first, price: "1")
        h.wake.wake() // the client now waits for the minimum attempt interval
        #expect(await h.hasSleeper(at: 2))
        #expect(await h.hasSleeper(at: 30))

        h.store.stop()
        #expect(await eventually { h.clock.sleeperCount == 0 })
        h.advance(to: 600)
        await settle()
        #expect(h.connectionCount == 1)
    }
}
