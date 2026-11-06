import Foundation
@testable import BitcoinTicker

final class FakeWebSocketConnection: WebSocketConnection, @unchecked Sendable {
    let url: URL
    let events: AsyncStream<WebSocketEvent>
    private let continuation: AsyncStream<WebSocketEvent>.Continuation
    private let lock = NSLock()
    private var closed = false

    init(url: URL) {
        self.url = url
        (events, continuation) = AsyncStream.makeStream()
    }

    var isClosed: Bool { lock.withLock { closed } }

    func send(_ event: WebSocketEvent) { continuation.yield(event) }

    func close() {
        lock.withLock { closed = true }
        continuation.finish()
    }
}

/// Hands each new connection to the test through `connections`.
final class FakeWebSocketTransport: WebSocketTransport, @unchecked Sendable {
    let connections: AsyncStream<FakeWebSocketConnection>
    private let continuation: AsyncStream<FakeWebSocketConnection>.Continuation

    init() {
        (connections, continuation) = AsyncStream.makeStream()
    }

    func connect(to url: URL) -> any WebSocketConnection {
        let connection = FakeWebSocketConnection(url: url)
        continuation.yield(connection)
        return connection
    }
}
