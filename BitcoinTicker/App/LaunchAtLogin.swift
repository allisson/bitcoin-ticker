import Observation
import ServiceManagement

/// The part of `SMAppService` the launch-at-login toggle uses, so tests can fake it.
protocol LoginItemService {
    var status: SMAppService.Status { get }
    func register() throws
    func unregister() throws
}

extension SMAppService: LoginItemService {}

/// Launch-at-login toggle state: the system status is the source of truth (spec §6.3).
@MainActor @Observable
final class LaunchAtLogin {
    private(set) var isEnabled = false
    private(set) var message: String?

    private let service: any LoginItemService

    init(service: any LoginItemService = SMAppService.mainApp) {
        self.service = service
    }

    /// Re-reads the system status; called on every popover open.
    func refresh() {
        apply(service.status, changed: false, failed: false)
    }

    func setEnabled(_ enabled: Bool) {
        var failed = false
        do {
            if enabled { try service.register() } else { try service.unregister() }
        } catch {
            failed = true
        }
        apply(service.status, changed: true, failed: failed)
    }

    /// A never-registered app also reports `.notFound`, so it only explains after a change attempt.
    private func apply(_ status: SMAppService.Status, changed: Bool, failed: Bool) {
        isEnabled = status == .enabled || status == .requiresApproval
        switch status {
        case .requiresApproval:
            message = "Approve Bitcoin Ticker in System Settings → General → Login Items"
        case .notFound where changed:
            message = "Launch at login is not available. Move the app to Applications and open it again"
        default:
            message = failed ? "Could not change Launch at login" : nil
        }
    }
}
