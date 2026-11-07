import Foundation
@testable import BitcoinTicker

/// A connection the test drives. `close()` only marks it closed and keeps the stream open, so a
/// test can still deliver messages after the close, as a real transport may.
final class FakeWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    let url: URL
    /// The manual clock's time when the client opened this connection.
    let startedAt: Duration
    let events: AsyncStream<WebSocketEvent>
    private let continuation: AsyncStream<WebSocketEvent>.Continuation
    private let lock = NSLock()
    private var closed = false

    init(url: URL, startedAt: Duration) {
        self.url = url
        self.startedAt = startedAt
        (events, continuation) = AsyncStream.makeStream()
    }

    var isClosed: Bool { lock.withLock { closed } }

    func send(_ event: WebSocketEvent) { continuation.yield(event) }

    func close() { lock.withLock { closed = true } }
}

/// Hands each new connection to the test through `connections`, and keeps them all in `all`.
final class FakeWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    let connections: AsyncStream<FakeWebSocketConnection>
    private let continuation: AsyncStream<FakeWebSocketConnection>.Continuation
    private let clock: ManualClock
    private let lock = NSLock()
    private var created: [FakeWebSocketConnection] = []

    init(clock: ManualClock) {
        self.clock = clock
        (connections, continuation) = AsyncStream.makeStream()
    }

    var all: [FakeWebSocketConnection] { lock.withLock { created } }

    func connect(to url: URL) -> any WebSocketConnection {
        let connection = FakeWebSocketConnection(url: url, startedAt: clock.now.offset)
        lock.withLock { created.append(connection) }
        continuation.yield(connection)
        return connection
    }
}

struct FixedRandomSource: RandomSource {
    let value: Double
    func nextUnit() -> Double { value }
}
