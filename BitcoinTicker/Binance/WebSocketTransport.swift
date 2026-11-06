import Foundation

/// One frame received from the WebSocket. Only text frames carry ticker messages (spec §5.3).
enum WebSocketFrame: Equatable, Sendable {
    case text(String)
    case binary(Data)
}

/// What one connection reports, in order. The stream ends after `handshakeFailed` or `closed`.
enum WebSocketEvent: Equatable, Sendable {
    /// The handshake completed (spec §5.5: from the session delegate, not from `receive()`).
    case opened
    case frame(WebSocketFrame)
    /// The upgrade failed: the HTTP status and raw `Retry-After` value, when readable (spec §5.2).
    case handshakeFailed(status: Int?, retryAfter: String?)
    /// An open connection closed, by either side or by a transport error.
    case closed
}

/// One WebSocket connection attempt, started by `WebSocketTransport.connect(to:)`.
protocol WebSocketConnection: AnyObject, Sendable {
    var events: AsyncStream<WebSocketEvent> { get }
    func close()
}

/// Opens connections, so the client runs in tests without the network (spec §5.5, §7).
protocol WebSocketTransport: Sendable {
    func connect(to url: URL) -> any WebSocketConnection
}
