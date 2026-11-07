import AppKit
import Network

/// Network-path reports, as `NWPathMonitor` sends them: the initial path, then every update.
protocol NetworkPathSource: Sendable {
    func statuses() -> AsyncStream<NWPath.Status>
}

/// One element per wake from sleep.
protocol WakeSource: Sendable {
    func wakes() -> AsyncStream<Void>
}

struct SystemNetworkPathSource: NetworkPathSource {
    func statuses() -> AsyncStream<NWPath.Status> {
        AsyncStream { continuation in
            let monitor = NWPathMonitor()
            monitor.pathUpdateHandler = { continuation.yield($0.status) }
            continuation.onTermination = { _ in monitor.cancel() }
            monitor.start(queue: DispatchQueue(label: "io.github.allisson.BitcoinTicker.path"))
        }
    }
}

struct SystemWakeSource: WakeSource {
    func wakes() -> AsyncStream<Void> {
        AsyncStream { continuation in
            let center = NSWorkspace.shared.notificationCenter
            let observer = center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: nil) { _ in
                continuation.yield()
            }
            nonisolated(unsafe) let token = observer // only removed, never used concurrently
            continuation.onTermination = { _ in center.removeObserver(token) }
        }
    }
}
