import Cocoa
import CoreGraphics

enum ModifierKey: String, CaseIterable, Hashable, Identifiable {
    var id: String { rawValue }

    case none
    case shift
    case option
    case control
    case command

    var shortLabel: String {
        switch self {
        case .none: return "None"
        case .shift: return "⇧ Shift"
        case .option: return "⌥ Option"
        case .control: return "⌃ Control"
        case .command: return "⌘ Command"
        }
    }

    var eventFlag: CGEventFlags? {
        switch self {
        case .none: return nil
        case .shift: return .maskShift
        case .option: return .maskAlternate
        case .control: return .maskControl
        case .command: return .maskCommand
        }
    }
}

final class Preferences {
    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    private enum Keys {
        static let isEnabled = "isEnabled"
        /// Home / default pin — where Dock should live.
        static let defaultDisplayID = "defaultDisplayID"
        /// Where we last intentionally placed the Dock (may differ from default).
        static let currentDockDisplayID = "currentDockDisplayID"
        /// Stable fingerprints (UUID/name) — CGDirectDisplayID alone is not stable across login.
        static let defaultDisplayFingerprint = "defaultDisplayFingerprint"
        static let currentDockFingerprint = "currentDockFingerprint"
        static let modifierKey = "modifierKey"
        static let restoreOnWake = "restoreOnWake"
        static let launchAtLogin = "launchAtLogin"
        static let triggerZonePixels = "triggerZonePixels"
        static let blockedDisplayIDs = "blockedDisplayIDs"
        static let lastUpdateCheckAt = "lastUpdateCheckAt"
        static let autoCheckForUpdates = "autoCheckForUpdates"
        static let autoInstallUpdates = "autoInstallUpdates"
        // Legacy key migration
        static let legacyAnchor = "anchorDisplayID"
    }

    var isEnabled: Bool {
        get {
            if defaults.object(forKey: Keys.isEnabled) == nil { return true }
            return defaults.bool(forKey: Keys.isEnabled)
        }
        set { defaults.set(newValue, forKey: Keys.isEnabled) }
    }

    /// Default home display for the Dock (last-known ID; may be stale after reboot).
    var defaultDisplayID: UInt32 {
        get {
            var value = defaults.integer(forKey: Keys.defaultDisplayID)
            if value == 0 {
                value = defaults.integer(forKey: Keys.legacyAnchor)
            }
            return UInt32(truncatingIfNeeded: value)
        }
        set {
            defaults.set(Int(newValue), forKey: Keys.defaultDisplayID)
            defaults.set(Int(newValue), forKey: Keys.legacyAnchor)
        }
    }

    /// Display where the Dock currently sits after an intentional move.
    var currentDockDisplayID: UInt32 {
        get {
            let value = defaults.integer(forKey: Keys.currentDockDisplayID)
            if value == 0 { return defaultDisplayID }
            return UInt32(truncatingIfNeeded: value)
        }
        set { defaults.set(Int(newValue), forKey: Keys.currentDockDisplayID) }
    }

    var defaultDisplayFingerprint: DisplayFingerprint? {
        get { decodeFingerprint(Keys.defaultDisplayFingerprint) }
        set { encodeFingerprint(newValue, key: Keys.defaultDisplayFingerprint) }
    }

    var currentDockFingerprint: DisplayFingerprint? {
        get { decodeFingerprint(Keys.currentDockFingerprint) }
        set { encodeFingerprint(newValue, key: Keys.currentDockFingerprint) }
    }

    /// Persist default by live display info (ID + stable fingerprint).
    func setDefaultDisplay(_ info: DisplayInfo) {
        defaultDisplayID = info.id
        defaultDisplayFingerprint = DisplayFingerprint.from(display: info)
    }

    func setCurrentDockDisplay(_ info: DisplayInfo) {
        currentDockDisplayID = info.id
        currentDockFingerprint = DisplayFingerprint.from(display: info)
    }

    private func decodeFingerprint(_ key: String) -> DisplayFingerprint? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(DisplayFingerprint.self, from: data)
    }

    private func encodeFingerprint(_ value: DisplayFingerprint?, key: String) {
        if let value, let data = try? JSONEncoder().encode(value) {
            defaults.set(data, forKey: key)
        } else {
            defaults.removeObject(forKey: key)
        }
    }

    /// Convenience alias used in older code paths.
    var anchorDisplayID: UInt32 {
        get { defaultDisplayID }
        set { defaultDisplayID = newValue }
    }

    var modifierKey: ModifierKey {
        get {
            let raw = defaults.string(forKey: Keys.modifierKey) ?? ModifierKey.shift.rawValue
            return ModifierKey(rawValue: raw) ?? .shift
        }
        set { defaults.set(newValue.rawValue, forKey: Keys.modifierKey) }
    }

    var restoreOnWake: Bool {
        get {
            if defaults.object(forKey: Keys.restoreOnWake) == nil { return true }
            return defaults.bool(forKey: Keys.restoreOnWake)
        }
        set { defaults.set(newValue, forKey: Keys.restoreOnWake) }
    }

    var launchAtLogin: Bool {
        get { defaults.bool(forKey: Keys.launchAtLogin) }
        set { defaults.set(newValue, forKey: Keys.launchAtLogin) }
    }

    /// Unix time of last successful/attempted update check (throttle).
    var lastUpdateCheckAt: TimeInterval {
        get { defaults.double(forKey: Keys.lastUpdateCheckAt) }
        set { defaults.set(newValue, forKey: Keys.lastUpdateCheckAt) }
    }

    /// Check GitHub Releases on launch and periodically.
    /// Default **off** (offline-first); user can enable explicitly.
    var autoCheckForUpdates: Bool {
        get {
            if defaults.object(forKey: Keys.autoCheckForUpdates) == nil { return false }
            return defaults.bool(forKey: Keys.autoCheckForUpdates)
        }
        set { defaults.set(newValue, forKey: Keys.autoCheckForUpdates) }
    }

    /// When a newer release is found, download and install without asking (default off).
    var autoInstallUpdates: Bool {
        get { defaults.bool(forKey: Keys.autoInstallUpdates) }
        set { defaults.set(newValue, forKey: Keys.autoInstallUpdates) }
    }

    var triggerZonePixels: CGFloat {
        get {
            let value = defaults.double(forKey: Keys.triggerZonePixels)
            return value > 0 ? CGFloat(value) : 6
        }
        set { defaults.set(Double(newValue), forKey: Keys.triggerZonePixels) }
    }

    /// Blacklist — Dock must never appear on these displays.
    var blockedDisplayIDs: Set<UInt32> {
        get {
            let arr = defaults.array(forKey: Keys.blockedDisplayIDs) as? [Int] ?? []
            return Set(arr.map { UInt32(truncatingIfNeeded: $0) })
        }
        set { defaults.set(newValue.map { Int($0) }, forKey: Keys.blockedDisplayIDs) }
    }

    func isBlocked(_ id: UInt32) -> Bool { blockedDisplayIDs.contains(id) }
    func isAllowed(_ id: UInt32) -> Bool { !isBlocked(id) }

    var dockIsAwayFromDefault: Bool {
        currentDockDisplayID != 0
            && defaultDisplayID != 0
            && currentDockDisplayID != defaultDisplayID
    }
}
