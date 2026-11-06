import Foundation

/// One frame received from the WebSocket. Only text frames carry ticker messages (spec §5.3).
enum WebSocketFrame: Equatable, Sendable {
    case text(String)
    case binary(Data)
}
