import Foundation
import os

struct URLSessionWebSocketTransport: WebSocketTransport {
    func connect(to url: URL) -> any WebSocketConnection {
        URLSessionWebSocketConnection(url: url)
    }
}

/// One `URLSessionWebSocketTask` with its own session, so the delegate callbacks belong to it alone.
final class URLSessionWebSocketConnection: NSObject, WebSocketConnection, URLSessionWebSocketDelegate,
    @unchecked Sendable {
    let events: AsyncStream<WebSocketEvent>
    private let continuation: AsyncStream<WebSocketEvent>.Continuation
    private let isOpen = OSAllocatedUnfairLock(initialState: false)
    // Set once in init, before any delegate callback can run.
    private var session: URLSession!
    private var task: URLSessionWebSocketTask!

    init(url: URL) {
        (events, continuation) = AsyncStream.makeStream()
        super.init()
        session = URLSession(configuration: .ephemeral, delegate: self, delegateQueue: nil)
        task = session.webSocketTask(with: url)
        task.resume()
    }

    func close() {
        continuation.finish()
        task.cancel(with: .goingAway, reason: nil)
        session.invalidateAndCancel()
    }

    func urlSession(_ session: URLSession, webSocketTask: URLSessionWebSocketTask, didOpenWithProtocol protocol: String?) {
        isOpen.withLock { $0 = true }
        continuation.yield(.opened)
        receiveNext()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if isOpen.withLock({ $0 }) {
            continuation.yield(.closed)
        } else {
            let response = task.response as? HTTPURLResponse
            continuation.yield(.handshakeFailed(
                status: response?.statusCode,
                retryAfter: response?.value(forHTTPHeaderField: "Retry-After")
            ))
        }
        continuation.finish()
        session.finishTasksAndInvalidate()
    }

    private func receiveNext() {
        task.receive { [weak self] result in
            guard let self else { return }
            switch result {
            case .success(.string(let text)):
                continuation.yield(.frame(.text(text)))
            case .success(.data(let data)):
                continuation.yield(.frame(.binary(data)))
            case .success:
                continuation.yield(.frame(.binary(Data())))
            case .failure:
                return // didCompleteWithError reports the close.
            }
            receiveNext()
        }
    }
}
