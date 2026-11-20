import Foundation
import ServiceManagement

/// Registers the app as a login item through the modern `SMAppService` API.
///
/// The toggle is driven by the real system status instead of a private flag, so
/// an item that was removed in System Settings immediately reads as off.
@MainActor
enum LoginItemController {
    static var status: SMAppService.Status { SMAppService.mainApp.status }

    static var isEnabled: Bool { status == .enabled }

    /// The registration exists but waits for the user in Login Items.
    static var requiresApproval: Bool { status == .requiresApproval }

    /// Registers or unregisters the main app. Registration can fail when the
    /// app is not in Applications or when the current signature is not accepted
    /// yet; the settings row surfaces the error and points at Login Items.
    static func setEnabled(_ enabled: Bool) throws {
        let service = SMAppService.mainApp
        if enabled {
            guard service.status != .enabled, service.status != .requiresApproval else {
                return
            }
            try service.register()
        } else {
            guard service.status != .notRegistered else { return }
            try service.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}
