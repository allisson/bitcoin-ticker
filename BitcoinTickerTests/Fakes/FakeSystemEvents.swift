import Network
@testable import BitcoinTicker

final class FakeNetworkPathSource: NetworkPathSource {
    private let stream: AsyncStream<NWPath.Status>
    private let continuation: AsyncStream<NWPath.Status>.Continuation

    init() { (stream, continuation) = AsyncStream.makeStream() }

    func statuses() -> AsyncStream<NWPath.Status> { stream }

    func send(_ status: NWPath.Status) { continuation.yield(status) }
}

final class FakeWakeSource: WakeSource {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation

    init() { (stream, continuation) = AsyncStream.makeStream() }

    func wakes() -> AsyncStream<Void> { stream }

    func wake() { continuation.yield() }
}
