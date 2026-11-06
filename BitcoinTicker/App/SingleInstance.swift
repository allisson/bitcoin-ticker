import AppKit

/// The launch identity of one running copy of the app (spec §7).
struct InstanceInfo: Equatable {
    let processIdentifier: pid_t
    let launchDate: Date?
}

enum SingleInstance {
    /// Whether `current` must quit because another running copy wins: the one launched earlier,
    /// or, when the dates are equal or missing, the one with the lower process identifier.
    static func shouldQuit(current: InstanceInfo, others: [InstanceInfo]) -> Bool {
        others.contains { other in
            guard other.processIdentifier != current.processIdentifier else { return false }
            if let otherDate = other.launchDate, let currentDate = current.launchDate, otherDate != currentDate {
                return otherDate < currentDate
            }
            return current.processIdentifier > other.processIdentifier
        }
    }

    /// Reads the running copies with this bundle identifier and applies `shouldQuit`.
    @MainActor
    static func shouldQuitAtLaunch() -> Bool {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return false }
        // NSRunningApplication.current reports pid -1 before LaunchServices registers the process
        // (for example, when the binary is run directly), so take the pid from the kernel.
        let current = InstanceInfo(
            processIdentifier: ProcessInfo.processInfo.processIdentifier,
            launchDate: NSRunningApplication.current.launchDate
        )
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            .map { InstanceInfo(processIdentifier: $0.processIdentifier, launchDate: $0.launchDate) }
        return shouldQuit(current: current, others: others)
    }
}
