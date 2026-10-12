import Foundation
import ServiceManagement

/// Login item state lives in macOS (System Settings → General → Login Items), not in
/// our settings, so the user can change it there and we always read it fresh.
enum LaunchAtLogin {
    enum State: Equatable {
        case enabled
        case disabled
        /// Registered, but the user turned it off in System Settings.
        case requiresApproval
        /// Not running from an .app bundle (e.g. `swift run`); registration would fail.
        case unavailable
    }

    static var state: State {
        guard Bundle.main.bundleURL.pathExtension == "app" else {
            return .unavailable
        }
        switch SMAppService.mainApp.status {
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notRegistered, .notFound:
            return .disabled
        @unknown default:
            return .disabled
        }
    }

    static func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
