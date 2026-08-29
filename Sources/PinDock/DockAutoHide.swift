import Foundation
import Darwin

/// macOS Dock “Automatically hide and show the Dock” (System Settings → Desktop & Dock).
enum DockAutoHide {
    static var isEnabled: Bool {
        get { read() }
        set { write(newValue) }
    }

    static func read() -> Bool {
        if let getAutoHide {
            return getAutoHide() != 0
        }
        return UserDefaults(suiteName: "com.apple.dock")?.bool(forKey: "autohide") ?? false
    }

    static func write(_ enabled: Bool) {
        if let setAutoHide {
            setAutoHide(enabled ? 1 : 0)
            return
        }
        fallbackWrite(enabled)
    }

    // MARK: - CoreDock (HIServices, no Dock relaunch)

    private static let getAutoHide: (@convention(c) () -> UInt8)? = load("CoreDockGetAutoHideEnabled")
    private static let setAutoHide: (@convention(c) (UInt8) -> Void)? = load("CoreDockSetAutoHideEnabled")

    private static func load<T>(_ name: String) -> T? {
        guard let symbol = dlsym(UnsafeMutableRawPointer(bitPattern: -2), name) else {
            return nil
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    /// Last resort: persist the pref and restart Dock (brief flash).
    private static func fallbackWrite(_ enabled: Bool) {
        let defaults = UserDefaults(suiteName: "com.apple.dock")
        defaults?.set(enabled, forKey: "autohide")
        defaults?.synchronize()
        DistributedNotificationCenter.default().postNotificationName(
            Notification.Name("com.apple.dock.prefschanged"),
            object: "com.apple.dock",
            userInfo: nil,
            deliverImmediately: true
        )
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Dock"]
        try? task.run()
    }
}
