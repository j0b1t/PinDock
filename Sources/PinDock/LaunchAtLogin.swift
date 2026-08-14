import Foundation
import ServiceManagement

enum LaunchAtLogin {
    static var isEnabled: Bool {
        get {
            if #available(macOS 13.0, *) {
                return SMAppService.mainApp.status == .enabled
            }
            return Preferences.shared.launchAtLogin
        }
        set {
            Preferences.shared.launchAtLogin = newValue
            if #available(macOS 13.0, *) {
                do {
                    if newValue {
                        try SMAppService.mainApp.register()
                    } else {
                        try SMAppService.mainApp.unregister()
                    }
                } catch {
                    NSLog("PinDock: Launch at login failed: \(error.localizedDescription)")
                }
            }
        }
    }

    static func syncFromPreferences() {
        // SMAppService only works reliably inside a real .app bundle.
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }
        if #available(macOS 13.0, *) {
            let desired = Preferences.shared.launchAtLogin
            let actual = SMAppService.mainApp.status == .enabled
            if desired != actual {
                isEnabled = desired
            }
        }
    }
}
