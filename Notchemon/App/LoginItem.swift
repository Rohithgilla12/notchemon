import AppKit
import Observation
import ServiceManagement

enum LoginItemState: Equatable {
    case off
    case on
    /// Registered, but the user turned it off in System Settings, which is
    /// the only place it can be turned back on.
    case needsApproval

    init(_ status: SMAppService.Status) {
        switch status {
        case .enabled: self = .on
        case .requiresApproval: self = .needsApproval
        case .notRegistered, .notFound: self = .off
        @unknown default: self = .off
        }
    }
}

/// Launch at login through `SMAppService.mainApp`. Registers only when the
/// user asks, and rereads the status each time a menu opens, since the user
/// can change it in System Settings at any time.
@MainActor
@Observable
final class LoginItem {
    private(set) var state: LoginItemState
    @ObservationIgnored private var menuObserver: NSObjectProtocol?

    init() {
        state = LoginItemState(SMAppService.mainApp.status)
        menuObserver = NotificationCenter.default.addObserver(
            forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func toggle() {
        let service = SMAppService.mainApp
        do {
            switch state {
            case .off: try service.register()
            case .on: try service.unregister()
            case .needsApproval: SMAppService.openSystemSettingsLoginItems()
            }
        } catch {
            NSApp.activate()
            NSAlert(error: error).runModal()
        }
        refresh()
    }

    private func refresh() {
        state = LoginItemState(SMAppService.mainApp.status)
    }
}
