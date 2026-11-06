import Foundation
import Testing
@testable import BitcoinTicker

/// A client wired to a manual clock, a fake transport, and a fixed random source.
struct ClientHarness {
    static let url = URL(string: "ws://127.0.0.1:8080")!

    let clock = ManualClock()
    let transport: FakeWebSocketTransport
    let client: BinanceWebSocketClient<ManualClock>
    private let events: StreamRecorder<ClientEvent>
    private let connections: StreamRecorder<FakeWebSocketConnection>

    /// `random` 1 makes every backoff delay its upper bound.
    init(_ configuration: ClientConfiguration = ClientConfiguration(), random: Double = 1) {
        transport = FakeWebSocketTransport(clock: clock)
        client = BinanceWebSocketClient(
            url: Self.url, transport: transport, clock: clock,
            random: FixedRandomSource(value: random), configuration: configuration
        )
        events = StreamRecorder(client.events)
        connections = StreamRecorder(transport.connections)
    }

    /// A configuration without the minimum attempt interval, so backoff delays show unchanged.
    static let noMinimumInterval: ClientConfiguration = {
        var configuration = ClientConfiguration()
        configuration.minimumAttemptInterval = .zero
        return configuration
    }()

    func nextConnection() async throws -> FakeWebSocketConnection {
        try #require(await connections.next())
    }

    func nextEvent() async -> ClientEvent? {
        await events.next()
    }

    /// The next state change, skipping ticker events.
    func nextState() async -> ConnectionState? {
        while let event = await events.next() {
            if case .state(let state) = event { return state }
        }
        return nil
    }

    /// Whether the client is sleeping until `seconds` on the manual clock.
    func hasSleeper(at seconds: Double) async -> Bool {
        await eventually { clock.deadlines.contains(.seconds(seconds)) }
    }

    func advance(to seconds: Double) {
        clock.advance(to: .seconds(seconds))
    }

    /// Fails the connection's handshake with `status`.
    func reject(_ connection: FakeWebSocketConnection, status: Int?, retryAfter: String? = nil) {
        connection.send(.handshakeFailed(status: status, retryAfter: retryAfter))
    }

    static func ticker(price: String = "67432.18") -> WebSocketEvent {
        .frame(.text(BinanceTickerMessageTests.payload(c: "\"\(price)\"")))
    }
}

struct BinanceWebSocketClientTests {
    // MARK: Handshake and messages (M1)

    @Test func reportsConnectedOnlyAfterHandshake() async throws {
        let h = ClientHarness()
        await h.client.start()
        let connection = try await h.nextConnection()
        #expect(connection.url == ClientHarness.url)
        #expect(await h.nextState() == .connecting)
        connection.send(.opened)
        #expect(await h.nextState() == .connected)
        await h.client.stop()
    }

    @Test func emitsValidTickersAndSkipsMalformedOnes() async throws {
        let h = ClientHarness()
        await h.client.start()
        let connection = try await h.nextConnection()
        connection.send(.opened)
        connection.send(.frame(.text("not json")))
        connection.send(.frame(.binary(Data(BinanceTickerMessageTests.payload().utf8))))
        connection.send(.frame(.text(BinanceTickerMessageTests.payload(s: "\"ETHUSDT\""))))
        connection.send(ClientHarness.ticker())
        #expect(await h.nextEvent() == .state(.connecting))
        #expect(await h.nextEvent() == .state(.connected))
        let expected = try #require(BinanceTickerMessage(text: BinanceTickerMessageTests.payload()))
        #expect(await h.nextEvent() == .ticker(expected))
        #expect(!connection.isClosed)
        await h.client.stop()
    }

    @Test(arguments: [(451, ConnectionState.unavailable), (403, .unavailable), (429, .rateLimited), (418, .rateLimited)])
    func rejectedHandshakeOnTheFirstAttemptMapsStatus(status: Int, expected: ConnectionState) async throws {
        let h = ClientHarness()
        await h.client.start()
        h.reject(try await h.nextConnection(), status: status)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == expected)
        await h.client.stop()
    }

    @Test(arguments: [
        (451, false, ConnectionState.unavailable), (403, true, .unavailable),
        (429, false, .rateLimited), (418, true, .rateLimited),
        (500, false, .connecting), (404, true, .reconnecting),
        (nil, false, .connecting), (nil, true, .reconnecting),
    ] as [(Int?, Bool, ConnectionState)])
    func rejectedHandshakeStateTable(status: Int?, hasConnected: Bool, expected: ConnectionState) {
        #expect(ConnectionState.afterRejectedHandshake(status: status, hasConnected: hasConnected) == expected)
    }

    // MARK: State transitions

    @Test func otherStatusesKeepConnectingThenReconnectingWithBackoff() async throws {
        let h = ClientHarness()
        await h.client.start()
        #expect(await h.nextState() == .connecting)
        h.reject(try await h.nextConnection(), status: 500)
        // Backoff for k = 1 is 1 s; the minimum attempt interval moves the retry to 2 s.
        #expect(await h.hasSleeper(at: 2))
        h.advance(to: 2)
        let second = try await h.nextConnection()
        h.reject(second, status: nil)
        #expect(await h.hasSleeper(at: 4)) // k = 2: 2 s
        h.advance(to: 4)
        let third = try await h.nextConnection()
        third.send(.opened)
        #expect(await h.nextState() == .connected) // Connecting throughout, never another state
        third.send(.closed)
        #expect(await h.nextState() == .reconnecting)
        #expect(await h.hasSleeper(at: 8)) // closed before stable: k = 3, 4 s
        h.advance(to: 8)
        h.reject(try await h.nextConnection(), status: 503)
        #expect(await h.hasSleeper(at: 16)) // k = 4: 8 s
        h.advance(to: 16)
        let fifth = try await h.nextConnection()
        h.reject(fifth, status: nil)
        #expect(await h.hasSleeper(at: 32))
        h.advance(to: 32)
        (try await h.nextConnection()).send(.opened)
        #expect(await h.nextState() == .connected) // Reconnecting throughout
        await h.client.stop()
    }

    @Test func startingOfflineConnectsWhenThePathReturns() async throws {
        let h = ClientHarness()
        await h.client.setNetworkAvailable(false)
        await h.client.start()
        #expect(await h.nextState() == .offline)
        await settle()
        #expect(h.transport.all.isEmpty)
        await h.client.setNetworkAvailable(true)
        #expect(await h.nextState() == .connecting)
        let first = try await h.nextConnection()
        first.send(.opened)
        #expect(await h.nextState() == .connected)
        await h.client.setNetworkAvailable(false)
        #expect(await h.nextState() == .offline)
        #expect(first.isClosed)
        await h.client.setNetworkAvailable(true)
        #expect(await h.nextState() == .reconnecting)
        #expect(await h.hasSleeper(at: 2)) // minimum attempt interval since the first attempt
        h.advance(to: 2)
        _ = try await h.nextConnection()
        await h.client.stop()
    }

    @Test func pathReturningDuringAFixedDelayRestoresUnavailable() async throws {
        let h = ClientHarness()
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 451)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .unavailable)
        #expect(await h.hasSleeper(at: 60))
        await h.client.setNetworkAvailable(false)
        #expect(await h.nextState() == .offline)
        h.advance(to: 30)
        await h.client.setNetworkAvailable(true)
        #expect(await h.nextState() == .unavailable)
        #expect(await h.hasSleeper(at: 60))
        h.advance(to: 59)
        await settle()
        #expect(h.transport.all.count == 1)
        h.advance(to: 60)
        let second = try await h.nextConnection()
        second.send(.opened)
        #expect(await h.nextState() == .connected) // Unavailable during the attempt, not Connecting
        await h.client.stop()
    }

    @Test(arguments: [(451, ConnectionState.unavailable), (429, .rateLimited)])
    func fixedDelayEndingWhileOfflineKeepsItsState(status: Int, expected: ConnectionState) async throws {
        let h = ClientHarness()
        await h.client.start()
        h.reject(try await h.nextConnection(), status: status)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == expected)
        await h.client.setNetworkAvailable(false)
        #expect(await h.nextState() == .offline)
        h.advance(to: 100)
        await settle()
        #expect(h.transport.all.count == 1)
        await h.client.setNetworkAvailable(true)
        #expect(await h.nextState() == expected)
        let second = try await h.nextConnection()
        #expect(second.startedAt == .seconds(100))
        second.send(.opened)
        #expect(await h.nextState() == .connected)
        await h.client.stop()
    }

    @Test func goingOfflineAbandonsAHandshake() async throws {
        let h = ClientHarness()
        await h.client.start()
        let first = try await h.nextConnection()
        #expect(await h.nextState() == .connecting)
        await h.client.setNetworkAvailable(false)
        #expect(await h.nextState() == .offline)
        #expect(first.isClosed)
        h.advance(to: 10) // the handshake timeout would have fired here
        await settle()
        #expect(h.transport.all.count == 1)
        await h.client.setNetworkAvailable(true)
        #expect(await h.nextState() == .connecting)
        _ = try await h.nextConnection()
        await h.client.stop()
    }

    // MARK: reconnect() and the minimum attempt interval

    @Test func reconnectDuringBackoffSkipsItWithoutIncrementingK() async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 1))
        h.advance(to: 1)
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 3)) // k = 2
        await h.client.reconnect()
        let third = try await h.nextConnection()
        #expect(third.startedAt == .seconds(1))
        h.reject(third, status: 500)
        #expect(await h.hasSleeper(at: 5)) // k = 3: 4 s, so reconnect() left k alone
        await h.client.stop()
    }

    @Test func reconnectWaitsForTheMinimumAttemptInterval() async throws {
        let h = ClientHarness()
        await h.client.start()
        let first = try await h.nextConnection()
        first.send(.opened)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .connected)
        h.advance(to: 0.5)
        await h.client.reconnect()
        #expect(await h.nextState() == .reconnecting)
        #expect(first.isClosed)
        await h.client.reconnect()
        await h.client.reconnect()
        await h.client.reconnect()
        #expect(await h.hasSleeper(at: 2))
        h.advance(to: 2)
        let second = try await h.nextConnection()
        #expect(second.startedAt == .seconds(2))
        await h.client.reconnect() // during the handshake: nothing
        await settle()
        #expect(h.transport.all.count == 2)
        #expect(!second.isClosed)
        await h.client.stop()
    }

    @Test func flappingPathAndRepeatedReconnectsRespectTheMinimumInterval() async throws {
        let h = ClientHarness()
        await h.client.start()
        (try await h.nextConnection()).send(.opened)
        for step in 1...16 {
            h.advance(to: Double(step) * 0.5)
            await h.client.setNetworkAvailable(false)
            await h.client.setNetworkAvailable(true)
            await h.client.reconnect()
            await h.client.reconnect()
            await settle()
            for connection in h.transport.all.suffix(1) { connection.send(.opened) }
        }
        let connections = h.transport.all
        #expect(connections.count > 1)
        for (earlier, later) in zip(connections, connections.dropFirst()) {
            #expect(later.startedAt - earlier.startedAt >= .seconds(2))
        }
        // Never two connections at once: every connection but the last is closed.
        let openEarlier = connections.dropLast().filter { !$0.isClosed }
        #expect(openEarlier.isEmpty)
        await h.client.stop()
    }

    @Test func leavingOfflineDoesNotChangeK() async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 1))
        h.advance(to: 1)
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 3)) // k = 3 next
        await h.client.setNetworkAvailable(false)
        await h.client.setNetworkAvailable(true)
        let third = try await h.nextConnection()
        h.reject(third, status: 500)
        #expect(await h.hasSleeper(at: 5)) // k = 3: 4 s
        await h.client.stop()
    }

    @Test(arguments: [true, false])
    func closingAnUnstableConnectionOurselvesDoesNotIncrementK(byReconnect: Bool) async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 500) // k = 2 next
        #expect(await h.hasSleeper(at: 1))
        h.advance(to: 1)
        let second = try await h.nextConnection()
        second.send(.opened)
        second.send(ClientHarness.ticker())
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .connected)
        if byReconnect {
            await h.client.reconnect()
        } else {
            await h.client.setNetworkAvailable(false)
            await h.client.setNetworkAvailable(true)
        }
        #expect(second.isClosed)
        let third = try await h.nextConnection()
        h.reject(third, status: 500)
        #expect(await h.hasSleeper(at: 3)) // still k = 2: 2 s
        await h.client.stop()
    }

    @Test func reconnectDuringAFixedDelayDoesNotShortenIt() async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 418, retryAfter: "90")
        #expect(await h.hasSleeper(at: 90))
        await h.client.reconnect()
        h.advance(to: 89)
        await h.client.reconnect()
        await settle()
        #expect(h.transport.all.count == 1)
        h.advance(to: 90)
        let next = try await h.nextConnection()
        #expect(next.startedAt == .seconds(90))
        await h.client.stop()
    }

    @Test func fixedDelayCountsThroughOffline() async throws {
        let h = ClientHarness()
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 429)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .rateLimited)
        h.advance(to: 10)
        await h.client.setNetworkAvailable(false)
        #expect(await h.nextState() == .offline)
        h.advance(to: 30)
        await h.client.setNetworkAvailable(true)
        #expect(await h.nextState() == .rateLimited)
        #expect(await h.hasSleeper(at: 60))
        h.advance(to: 60)
        let next = try await h.nextConnection()
        #expect(next.startedAt == .seconds(60))
        await h.client.stop()
    }

    // MARK: Delays

    @Test func handshakeTimeoutFailsTheAttempt() async throws {
        let h = ClientHarness()
        await h.client.start()
        let first = try await h.nextConnection()
        #expect(await h.hasSleeper(at: 10))
        h.advance(to: 10)
        #expect(await eventually { first.isClosed })
        #expect(await h.hasSleeper(at: 11)) // k = 1 backoff
        h.advance(to: 11)
        let second = try await h.nextConnection()
        second.send(.opened)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .connected)
        await h.client.stop()
    }

    @Test func fixedDelayStatesStayDuringTheirAttemptAndSwitchOnANewRejection() async throws {
        let h = ClientHarness()
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 451)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .unavailable)
        h.advance(to: 60)
        h.reject(try await h.nextConnection(), status: 429, retryAfter: "120")
        #expect(await h.nextState() == .rateLimited) // Unavailable during the attempt, then Rate limited
        #expect(await h.hasSleeper(at: 180))
        h.advance(to: 180)
        h.reject(try await h.nextConnection(), status: 403)
        #expect(await h.nextState() == .unavailable) // Rate limited during the attempt
        #expect(await h.hasSleeper(at: 240))
        h.advance(to: 240)
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.nextState() == .connecting) // other failure: normal backoff from k = 1
        #expect(await h.hasSleeper(at: 242))
        await h.client.stop()
    }

    @Test func backoffDoublesUpToTheCap() async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        var now = 0.0
        for delay in [1.0, 2, 4, 8, 16, 32, 60, 60] {
            h.reject(try await h.nextConnection(), status: 500)
            now += delay
            #expect(await h.hasSleeper(at: now))
            h.advance(to: now)
        }
        await h.client.stop()
    }

    @Test func backoffAppliesTheJitterFraction() {
        let configuration = ClientConfiguration()
        #expect(configuration.backoffDelay(k: 3, unit: 0.25) == .seconds(1))
        #expect(configuration.backoffDelay(k: 3, unit: 0) == .zero)
        #expect(configuration.backoffDelay(k: 1, unit: 1) == .seconds(1))
        #expect(configuration.backoffDelay(k: 1000, unit: 1) == .seconds(60))
    }

    @Test func stableConnectionResetsBackoff() async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 1))
        h.advance(to: 1)
        h.reject(try await h.nextConnection(), status: 500) // k = 3 next
        #expect(await h.hasSleeper(at: 3))
        h.advance(to: 3)
        let third = try await h.nextConnection()
        third.send(.opened)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .connected)
        h.advance(to: 33)
        third.send(ClientHarness.ticker())
        _ = await h.nextEvent() // the ticker: the connection is now stable
        third.send(.closed)
        #expect(await h.nextState() == .reconnecting)
        #expect(await h.hasSleeper(at: 34)) // k = 1: 1 s
        await h.client.stop()
    }

    @Test func messageThenCloseBeforeStabilityKeepsGrowingK() async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 1))
        h.advance(to: 1)
        h.reject(try await h.nextConnection(), status: 500) // k = 3 next
        #expect(await h.hasSleeper(at: 3))
        h.advance(to: 3)
        let third = try await h.nextConnection()
        third.send(.opened)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .connected)
        h.advance(to: 8)
        third.send(ClientHarness.ticker())
        _ = await h.nextEvent() // the ticker
        h.advance(to: 13)
        third.send(.closed)
        #expect(await h.hasSleeper(at: 17)) // k = 3: 4 s
        h.advance(to: 17)
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 25)) // k = 4: 8 s
        await h.client.stop()
    }

    @Test(arguments: [
        (String?.none, 60.0), ("120", 120), ("Wed, 21 Oct 2026 07:28:00 GMT", 60), ("30", 60), ("", 60),
        ("-5", 60), (" 120", 60), ("1.5", 60), ("259200", 259_200), ("999999", 259_200),
        ("99999999999999999999999999", 259_200),
    ] as [(String?, Double)])
    func fixedDelayFromRetryAfter(retryAfter: String?, seconds: Double) {
        #expect(ClientConfiguration().fixedDelay(retryAfter: retryAfter) == .seconds(seconds))
    }

    @Test func fixedDelayUsesRetryAfter() async throws {
        let h = ClientHarness()
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 429, retryAfter: "120")
        #expect(await h.hasSleeper(at: 120))
        await h.client.stop()
    }

    @Test(arguments: [false, true])
    func attemptAfterAFixedDelayRestartsBackoffAtK1(connectsFirst: Bool) async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 1))
        h.advance(to: 1)
        h.reject(try await h.nextConnection(), status: 500) // k = 3 next
        #expect(await h.hasSleeper(at: 3))
        h.advance(to: 3)
        h.reject(try await h.nextConnection(), status: 451)
        #expect(await h.hasSleeper(at: 63))
        h.advance(to: 63)
        let afterDelay = try await h.nextConnection()
        if connectsFirst {
            afterDelay.send(.opened)
            afterDelay.send(.closed)
        } else {
            h.reject(afterDelay, status: 500)
        }
        #expect(await h.hasSleeper(at: 64)) // k = 1: 1 s
        h.advance(to: 64)
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 65)) // that attempt left k at 1
        h.advance(to: 65)
        h.reject(try await h.nextConnection(), status: 500)
        #expect(await h.hasSleeper(at: 67)) // k = 2
        await h.client.stop()
    }

    @Test func dailyCloseReconnectsAfterTheK1Delay() async throws {
        let h = ClientHarness()
        await h.client.start()
        let first = try await h.nextConnection()
        first.send(.opened)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .connected)
        h.advance(to: 30)
        first.send(ClientHarness.ticker())
        _ = await h.nextEvent() // the ticker: stable
        h.advance(to: 86_400)
        first.send(.closed)
        #expect(await h.nextState() == .reconnecting)
        #expect(await h.hasSleeper(at: 86_401))
        h.advance(to: 86_401)
        (try await h.nextConnection()).send(.opened)
        #expect(await h.nextState() == .connected)
        await h.client.stop()
    }

    // MARK: Lifecycle

    @Test func stopCancelsTheHandshakeAndItsTimeout() async throws {
        let h = ClientHarness()
        await h.client.start()
        let connection = try await h.nextConnection()
        #expect(await h.hasSleeper(at: 10))
        await h.client.stop()
        #expect(connection.isClosed)
        #expect(await eventually { h.clock.deadlines.isEmpty })
        #expect(await h.nextEvent() == .state(.connecting))
        #expect(await h.nextEvent() == nil)
    }

    @Test func stopCancelsAPendingDelay() async throws {
        let h = ClientHarness()
        await h.client.start()
        h.reject(try await h.nextConnection(), status: 451)
        #expect(await h.hasSleeper(at: 60))
        await h.client.stop()
        #expect(await eventually { h.clock.deadlines.isEmpty })
        h.advance(to: 60)
        await settle()
        #expect(h.transport.all.count == 1)
    }

    @Test func messagesFromAReplacedConnectionAreDiscarded() async throws {
        let h = ClientHarness(ClientHarness.noMinimumInterval)
        await h.client.start()
        let first = try await h.nextConnection()
        first.send(.opened)
        #expect(await h.nextState() == .connecting)
        #expect(await h.nextState() == .connected)
        await h.client.reconnect()
        let second = try await h.nextConnection()
        #expect(first.isClosed)
        first.send(ClientHarness.ticker(price: "1.00"))
        first.send(.closed)
        second.send(.opened)
        second.send(ClientHarness.ticker(price: "2.00"))
        await settle()
        await h.client.stop()
        let expected = try #require(BinanceTickerMessage(text: BinanceTickerMessageTests.payload(c: "\"2.00\"")))
        var rest: [ClientEvent] = []
        while let event = await h.nextEvent() { rest.append(event) }
        #expect(rest == [.state(.reconnecting), .state(.connected), .ticker(expected)])
    }

    @Test func manualClockResumesSleepersOnlyAtTheirDeadline() async throws {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(5)) }
        #expect(await eventually { clock.sleeperCount == 1 })
        clock.advance(by: .seconds(4))
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .seconds(1))
        try await sleeper.value
        #expect(clock.sleeperCount == 0)
    }
}
