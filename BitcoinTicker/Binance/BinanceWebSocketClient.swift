import Foundation
import os

enum BinanceEndpoint {
    static let production = URL(string: "wss://stream.binance.com:443/ws/btcusdt@ticker")!

    /// Debug builds accept `-BinanceURL <url>` for manual tests; Release ignores it (spec §5.5).
    static var url: URL {
        #if DEBUG
        if let override = UserDefaults.standard.string(forKey: "BinanceURL"), let url = URL(string: override) {
            return url
        }
        #endif
        return production
    }
}

/// Owns the single Binance connection and its receive loop (spec §5.5, §7).
/// shortcut: one attempt only, no retry, backoff, or fixed delay; M2a adds them.
actor BinanceWebSocketClient {
    enum Event: Equatable, Sendable {
        case state(ConnectionState)
        case ticker(BinanceTickerMessage)
    }

    nonisolated let events: AsyncStream<Event>
    private let continuation: AsyncStream<Event>.Continuation
    private let url: URL
    private let transport: any WebSocketTransport
    private let logger = Logger(subsystem: Log.subsystem, category: "client")

    private var state: ConnectionState?
    private var hasConnected = false
    private var connection: (any WebSocketConnection)?
    private var receiveTask: Task<Void, Never>?

    init(url: URL, transport: any WebSocketTransport) {
        self.url = url
        self.transport = transport
        (events, continuation) = AsyncStream.makeStream()
    }

    func start() {
        guard connection == nil else { return }
        setState(hasConnected ? .reconnecting : .connecting)
        let connection = transport.connect(to: url)
        self.connection = connection
        receiveTask = Task { await self.receive(from: connection) }
    }

    func stop() {
        receiveTask?.cancel()
        receiveTask = nil
        connection?.close()
        connection = nil
        continuation.finish()
    }

    private func receive(from connection: any WebSocketConnection) async {
        var loggedMalformed = false
        for await event in connection.events {
            // Messages from a closed or replaced connection are discarded (spec §5.5).
            guard self.connection === connection else { return }
            switch event {
            case .opened:
                hasConnected = true
                setState(.connected)
            case .frame(let frame):
                if let message = BinanceTickerMessage(frame: frame) {
                    logger.debug("Ticker \(String(describing: message.lastPrice), privacy: .public) \(String(describing: message.priceChangePercent), privacy: .public)%")
                    continuation.yield(.ticker(message))
                } else if !loggedMalformed {
                    loggedMalformed = true
                    logger.error("Discarded a malformed message; further ones on this connection are not logged")
                }
            case .handshakeFailed(let status, let retryAfter):
                logger.notice("Handshake rejected, status \(status.map(String.init) ?? "unreadable", privacy: .public), Retry-After \(retryAfter ?? "none", privacy: .public)")
                setState(.afterRejectedHandshake(status: status, hasConnected: hasConnected))
            case .closed:
                setState(hasConnected ? .reconnecting : .connecting)
            }
        }
        if self.connection === connection {
            self.connection = nil
        }
    }

    private func setState(_ newState: ConnectionState) {
        guard newState != state else { return }
        state = newState
        logger.notice("Connection state: \(newState.rawValue, privacy: .public)")
        continuation.yield(.state(newState))
    }
}
