import Foundation
import Testing
@testable import BitcoinTicker

struct BinanceWebSocketClientTests {
    let url = URL(string: "ws://127.0.0.1:8080")!
    let transport = FakeWebSocketTransport()

    /// Starts a client and returns it with its event iterator and the connection it opened.
    func start() async throws -> (BinanceWebSocketClient, AsyncStream<BinanceWebSocketClient.Event>.Iterator, FakeWebSocketConnection) {
        let client = BinanceWebSocketClient(url: url, transport: transport)
        var events = client.events.makeAsyncIterator()
        await client.start()
        var connections = transport.connections.makeAsyncIterator()
        let connection = try #require(await connections.next())
        #expect(connection.url == url)
        #expect(await events.next() == .state(.connecting))
        return (client, events, connection)
    }

    @Test func reportsConnectedOnlyAfterHandshake() async throws {
        var (client, events, connection) = try await start()
        connection.send(.opened)
        #expect(await events.next() == .state(.connected))
        await client.stop()
    }

    @Test func emitsValidTickersAndSkipsMalformedOnes() async throws {
        var (client, events, connection) = try await start()
        connection.send(.opened)
        connection.send(.frame(.text("not json")))
        connection.send(.frame(.binary(Data(BinanceTickerMessageTests.payload().utf8))))
        connection.send(.frame(.text(BinanceTickerMessageTests.payload(s: "\"ETHUSDT\""))))
        connection.send(.frame(.text(BinanceTickerMessageTests.payload())))
        #expect(await events.next() == .state(.connected))
        let expected = try #require(BinanceTickerMessage(text: BinanceTickerMessageTests.payload()))
        #expect(await events.next() == .ticker(expected))
        #expect(!connection.isClosed)
        await client.stop()
    }

    @Test func closeAfterHandshakeReportsReconnecting() async throws {
        var (client, events, connection) = try await start()
        connection.send(.opened)
        connection.send(.closed)
        #expect(await events.next() == .state(.connected))
        #expect(await events.next() == .state(.reconnecting))
        await client.stop()
    }

    @Test(arguments: [(451, ConnectionState.unavailable), (403, .unavailable), (429, .rateLimited), (418, .rateLimited)])
    func rejectedHandshakeMapsStatus(status: Int, expected: ConnectionState) async throws {
        var (client, events, connection) = try await start()
        connection.send(.handshakeFailed(status: status, retryAfter: "120"))
        #expect(await events.next() == .state(expected))
        await client.stop()
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

    @Test func stopClosesTheConnectionAndEndsEvents() async throws {
        var (client, events, connection) = try await start()
        await client.stop()
        #expect(connection.isClosed)
        #expect(await events.next() == nil)
    }

    @Test func manualClockResumesSleepersOnlyAtTheirDeadline() async throws {
        let clock = ManualClock()
        let sleeper = Task { try await clock.sleep(for: .seconds(5)) }
        while clock.sleeperCount == 0 { await Task.yield() }
        clock.advance(by: .seconds(4))
        #expect(clock.sleeperCount == 1)
        clock.advance(by: .seconds(1))
        try await sleeper.value
        #expect(clock.sleeperCount == 0)
    }
}
