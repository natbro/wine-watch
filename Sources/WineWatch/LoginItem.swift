import Foundation
import ServiceManagement

/// "Launch automatically at startup", backed by SMAppService.
enum LoginItem {

    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    /// True once the user has denied the login item in System Settings; the
    /// only way back is the Login Items pane itself.
    static var requiresApproval: Bool {
        SMAppService.mainApp.status == .requiresApproval
    }

    static func set(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }

    /// SMAppService only works from a real bundle; `swift run` builds a bare
    /// executable, so the menu item is disabled there rather than throwing.
    static var isAvailable: Bool {
        Bundle.main.bundleIdentifier != nil && Bundle.main.bundlePath.hasSuffix(".app")
    }
}
