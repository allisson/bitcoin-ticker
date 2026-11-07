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

enum ClientEvent: Equatable, Sendable {
    case state(ConnectionState)
    case ticker(BinanceTickerMessage)
}

/// The client's intervals (spec §5.5), injectable so tests can change them.
struct ClientConfiguration: Sendable {
    var handshakeTimeout: Duration = .seconds(10)
    var backoffBase: Duration = .seconds(1)
    var backoffCap: Duration = .seconds(60)
    var stabilityInterval: Duration = .seconds(30)
    var minimumAttemptInterval: Duration = .seconds(2)
    var minimumFixedDelay: Duration = .seconds(60)
    var maximumFixedDelay: Duration = .seconds(3 * 24 * 60 * 60)

    /// Full jitter: `unit` (0...1) times `min(cap, base × 2^(k−1))`.
    func backoffDelay(k: Int, unit: Double) -> Duration {
        let exponent = min(max(k - 1, 0), 30)
        return min(backoffCap, backoffBase * (1 << exponent)) * unit
    }

    /// `Retry-After` as whole seconds only, at least the minimum and at most the maximum.
    func fixedDelay(retryAfter: String?) -> Duration {
        guard let retryAfter, !retryAfter.isEmpty, retryAfter.allSatisfy({ ("0"..."9").contains($0) }) else {
            return minimumFixedDelay
        }
        guard let seconds = Int(retryAfter) else { return maximumFixedDelay } // digits too large for Int
        return min(maximumFixedDelay, max(minimumFixedDelay, .seconds(seconds)))
    }
}

/// Owns the single Binance connection, its receive loop, and every retry rule of spec §5.5.
actor BinanceWebSocketClient<C: Clock<Duration>> {
    private enum Phase {
        /// Not started, stopped, or Offline: nothing scheduled.
        case idle
        /// Waiting for a backoff delay, a fixed delay, or the minimum attempt interval.
        case waiting
        case handshaking
        case connected
    }

    nonisolated let events: AsyncStream<ClientEvent>
    private let continuation: AsyncStream<ClientEvent>.Continuation
    private let url: URL
    private let transport: any WebSocketTransport
    private let clock: C
    private let random: any RandomSource
    private let configuration: ClientConfiguration
    private let logger = Logger(subsystem: Log.subsystem, category: "client")

    private var phase = Phase.idle
    private var isStarted = false
    private var isStopped = false
    private var isNetworkAvailable = true
    private var state: ConnectionState?
    private var hasConnected = false
    /// Index of the next backoff retry (spec §5.5).
    private var k = 1
    private var lastAttemptStart: C.Instant?
    /// End of a pending fixed delay; cleared when the attempt that follows it starts.
    private var fixedDelayEnd: C.Instant?
    /// Unavailable or Rate limited, kept until the attempt after the fixed delay succeeds or fails otherwise.
    private var fixedDelayState: ConnectionState?
    private var attemptEndsFixedDelay = false

    private var connection: (any WebSocketConnection)?
    private var connectionID = 0
    private var openedAt: C.Instant?
    private var isStable = false
    private var loggedMalformed = false
    private var receiveTask: Task<Void, Never>?
    private var timeoutTask: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?
    private var waitID = 0

    init(
        url: URL, transport: any WebSocketTransport, clock: C, random: any RandomSource,
        configuration: ClientConfiguration = ClientConfiguration()
    ) {
        self.url = url
        self.transport = transport
        self.clock = clock
        self.random = random
        self.configuration = configuration
        (events, continuation) = AsyncStream.makeStream()
    }

    private var retryState: ConnectionState { hasConnected ? .reconnecting : .connecting }

    func start() {
        guard !isStarted, !isStopped else { return }
        isStarted = true
        if isNetworkAvailable {
            startAttempt()
        } else {
            setState(.offline)
        }
    }

    /// Cancels the connection, the receive loop, and every pending delay.
    func stop() {
        guard !isStopped else { return }
        isStopped = true
        cancelWait()
        closeConnection()
        phase = .idle
        continuation.finish()
    }

    /// Starts an attempt as soon as the minimum attempt interval allows, skipping a backoff delay but
    /// never a fixed delay. Does nothing while Offline or during a handshake.
    func reconnect() {
        guard isStarted, !isStopped, isNetworkAvailable else { return }
        switch phase {
        case .connected:
            closeConnection()
            setState(.reconnecting)
            schedule(at: clock.now)
        case .waiting where fixedDelayEnd == nil:
            schedule(at: clock.now)
        case .waiting, .handshaking, .idle:
            return
        }
    }

    func setNetworkAvailable(_ available: Bool) {
        guard available != isNetworkAvailable else { return }
        isNetworkAvailable = available
        guard isStarted, !isStopped else { return }
        if available {
            setState(fixedDelayState ?? retryState)
            schedule(at: clock.now)
        } else {
            cancelWait()
            closeConnection()
            phase = .idle
            setState(.offline)
        }
    }

    // MARK: Attempts

    private func startAttempt() {
        lastAttemptStart = clock.now
        attemptEndsFixedDelay = fixedDelayState != nil
        fixedDelayEnd = nil
        setState(fixedDelayState ?? retryState)

        connectionID += 1
        let id = connectionID
        openedAt = nil
        isStable = false
        loggedMalformed = false
        let connection = transport.connect(to: url)
        self.connection = connection
        phase = .handshaking
        receiveTask = Task {
            for await event in connection.events {
                self.handle(event, connectionID: id)
            }
        }
        let timeout = configuration.handshakeTimeout
        timeoutTask = Task { [clock] in
            do { try await clock.sleep(for: timeout) } catch { return }
            self.handshakeTimedOut(connectionID: id)
        }
    }

    private func handle(_ event: WebSocketEvent, connectionID id: Int) {
        // Events from a closed or replaced connection are discarded (spec §5.5).
        guard id == connectionID, connection != nil else { return }
        switch event {
        case .opened:
            guard phase == .handshaking else { return }
            timeoutTask?.cancel()
            timeoutTask = nil
            phase = .connected
            hasConnected = true
            fixedDelayState = nil
            openedAt = clock.now
            setState(.connected)
        case .frame(let frame):
            guard phase == .connected else { return }
            guard let message = BinanceTickerMessage(frame: frame) else {
                if !loggedMalformed {
                    loggedMalformed = true
                    logger.error("Discarded a malformed message; further ones on this connection are not logged")
                }
                return
            }
            if !isStable, let openedAt, openedAt.duration(to: clock.now) >= configuration.stabilityInterval {
                isStable = true
                k = 1
            }
            logger.debug("Ticker \(String(describing: message.lastPrice), privacy: .public) \(String(describing: message.priceChangePercent), privacy: .public)%")
            continuation.yield(.ticker(message))
        case .handshakeFailed(let status, let retryAfter):
            guard phase == .handshaking else { return }
            logger.notice("Handshake rejected, status \(status.map(String.init) ?? "unreadable", privacy: .public), Retry-After \(retryAfter ?? "none", privacy: .public)")
            closeConnection()
            switch status {
            case 451, 403, 429, 418:
                startFixedDelay(.afterRejectedHandshake(status: status, hasConnected: hasConnected), retryAfter: retryAfter)
            default:
                retryAfterBackoff(failed: true)
            }
        case .closed:
            guard phase == .connected else { return }
            logger.notice("Connection closed \(self.isStable ? "after" : "before", privacy: .public) it was stable")
            closeConnection()
            retryAfterBackoff(failed: !isStable)
        }
    }

    private func handshakeTimedOut(connectionID id: Int) {
        guard id == connectionID, phase == .handshaking else { return }
        logger.notice("Handshake timed out")
        closeConnection()
        retryAfterBackoff(failed: true)
    }

    private func retryAfterBackoff(failed: Bool) {
        let delay = configuration.backoffDelay(k: k, unit: random.nextUnit())
        // The attempt that ends a fixed delay leaves k at 1.
        if failed, !attemptEndsFixedDelay { k += 1 }
        fixedDelayState = nil
        setState(retryState)
        schedule(at: clock.now.advanced(by: delay))
    }

    private func startFixedDelay(_ rejectedState: ConnectionState, retryAfter: String?) {
        k = 1
        fixedDelayState = rejectedState
        let end = clock.now.advanced(by: configuration.fixedDelay(retryAfter: retryAfter))
        fixedDelayEnd = end
        setState(rejectedState)
        schedule(at: end)
    }

    /// Schedules the next attempt no earlier than `target`, the minimum attempt interval, and a
    /// pending fixed delay. Replaces any earlier schedule, so only one attempt can start.
    private func schedule(at target: C.Instant) {
        var target = target
        if let lastAttemptStart {
            target = max(target, lastAttemptStart.advanced(by: configuration.minimumAttemptInterval))
        }
        if let fixedDelayEnd {
            target = max(target, fixedDelayEnd)
        }
        cancelWait()
        phase = .waiting
        let id = waitID
        waitTask = Task { [clock] in
            do { try await clock.sleep(until: target, tolerance: nil) } catch { return }
            self.waitEnded(waitID: id)
        }
    }

    private func waitEnded(waitID id: Int) {
        guard id == waitID, phase == .waiting, isNetworkAvailable, !isStopped else { return }
        waitTask = nil
        startAttempt()
    }

    private func cancelWait() {
        waitID += 1
        waitTask?.cancel()
        waitTask = nil
    }

    private func closeConnection() {
        timeoutTask?.cancel()
        timeoutTask = nil
        receiveTask?.cancel()
        receiveTask = nil
        connection?.close()
        connection = nil
    }

    private func setState(_ newState: ConnectionState) {
        guard newState != state else { return }
        state = newState
        logger.notice("Connection state: \(newState.rawValue, privacy: .public)")
        continuation.yield(.state(newState))
    }
}
