import ServiceManagement
import Testing
@testable import BitcoinTicker

final class FakeLoginItemService: LoginItemService {
    struct Failure: Error {}

    var status: SMAppService.Status
    /// Status the system reports after a successful `register()`.
    var statusAfterRegister: SMAppService.Status = .enabled
    var fails = false

    init(status: SMAppService.Status) { self.status = status }

    func register() throws {
        if fails { throw Failure() }
        status = statusAfterRegister
    }

    func unregister() throws {
        if fails { throw Failure() }
        status = .notRegistered
    }
}

@MainActor
struct LaunchAtLoginTests {
    @Test func refreshReadsTheSystemStatus() {
        let service = FakeLoginItemService(status: .notRegistered)
        let model = LaunchAtLogin(service: service)
        model.refresh()
        #expect(!model.isEnabled)

        service.status = .enabled // changed in System Settings while the app runs
        model.refresh()
        #expect(model.isEnabled)
        #expect(model.message == nil)
    }

    @Test func registerAndUnregister() {
        let service = FakeLoginItemService(status: .notRegistered)
        let model = LaunchAtLogin(service: service)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(service.status == .enabled)
        model.setEnabled(false)
        #expect(!model.isEnabled)
        #expect(service.status == .notRegistered)
    }

    @Test func requiresApprovalStaysOnAndExplains() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.statusAfterRegister = .requiresApproval
        let model = LaunchAtLogin(service: service)
        model.setEnabled(true)
        #expect(model.isEnabled)
        #expect(model.message == "Approve Bitcoin Ticker in System Settings → General → Login Items")
    }

    @Test func errorRevertsToTheSystemStatusWithAMessage() {
        let service = FakeLoginItemService(status: .notRegistered)
        service.fails = true
        let model = LaunchAtLogin(service: service)
        model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.message == "Could not change Launch at login")

        service.fails = false
        model.refresh() // the next open clears the message; no automatic retry
        #expect(model.message == nil)
        #expect(service.status == .notRegistered)
    }

    @Test func notFoundBeforeAnyChangeIsOffWithoutAMessage() {
        // A never-registered app reports `.notFound` too (macOS 26.6.2, roadmap §9).
        let model = LaunchAtLogin(service: FakeLoginItemService(status: .notFound))
        model.refresh()
        #expect(!model.isEnabled)
        #expect(model.message == nil)
    }

    @Test func notFoundAfterRegisteringExplains() {
        let service = FakeLoginItemService(status: .notFound)
        service.statusAfterRegister = .notFound // for example, a translocated copy
        let model = LaunchAtLogin(service: service)
        model.setEnabled(true)
        #expect(!model.isEnabled)
        #expect(model.message == "Launch at login is not available. Move the app to Applications and open it again")
    }
}
