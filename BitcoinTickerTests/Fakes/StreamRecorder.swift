import Foundation

/// Consumes a stream on its own task, so a test can read it in order without holding an iterator.
final class StreamRecorder<Element: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [Element] = []
    private var finished = false
    private var cursor = 0

    init(_ stream: AsyncStream<Element>) {
        Task {
            for await item in stream {
                self.lock.withLock { self.items.append(item) }
            }
            self.lock.withLock { self.finished = true }
        }
    }

    /// The next unread element, or `nil` once the stream has finished (or after the wait limit).
    func next() async -> Element? {
        _ = await eventually { self.lock.withLock { self.cursor < self.items.count || self.finished } }
        return lock.withLock {
            guard cursor < items.count else { return nil }
            defer { cursor += 1 }
            return items[cursor]
        }
    }
}
