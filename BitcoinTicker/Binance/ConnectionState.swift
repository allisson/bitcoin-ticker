/// Connection state (spec §5.7). Raw values are the names logged on every change (spec §9).
enum ConnectionState: String, Equatable, Sendable {
    case connecting = "Connecting"
    case connected = "Connected"
    case reconnecting = "Reconnecting"
    case rateLimited = "Rate limited"
    case offline = "Offline"
    case unavailable = "Unavailable"

    /// The state after a rejected handshake, by HTTP status (spec §5.2).
    static func afterRejectedHandshake(status: Int?, hasConnected: Bool) -> ConnectionState {
        switch status {
        case 451, 403: .unavailable
        case 429, 418: .rateLimited
        default: hasConnected ? .reconnecting : .connecting
        }
    }
}
