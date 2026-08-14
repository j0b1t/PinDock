import SwiftUI
import Combine
import AppKit

final class AppState: ObservableObject {
    static let shared = AppState()

    @Published var isEnabled: Bool {
        didSet {
            Preferences.shared.isEnabled = isEnabled
            if isEnabled {
                PinDockEngine.shared.start()
            } else {
                PinDockEngine.shared.stop()
            }
            refreshStatus()
        }
    }

    /// Home display — only “Set as default” changes this.
    @Published var defaultDisplayID: UInt32 {
        didSet {
            Preferences.shared.defaultDisplayID = defaultDisplayID
            refreshStatus()
        }
    }

    @Published var currentDockDisplayID: UInt32 {
        didSet {
            Preferences.shared.currentDockDisplayID = currentDockDisplayID
            refreshStatus()
        }
    }

    @Published private(set) var actualDockDisplayID: UInt32 = 0

    @Published var modifierKey: ModifierKey {
        didSet { Preferences.shared.modifierKey = modifierKey }
    }

    @Published var restoreOnWake: Bool {
        didSet { Preferences.shared.restoreOnWake = restoreOnWake }
    }

    @Published var launchAtLogin: Bool {
        didSet { LaunchAtLogin.isEnabled = launchAtLogin }
    }

    @Published var blockedDisplayIDs: Set<UInt32> {
        didSet { Preferences.shared.blockedDisplayIDs = blockedDisplayIDs }
    }

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var isTrusted: Bool = false
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var statusLine: String = ""
    @Published private(set) var dockIsAway: Bool = false

    // Updates (GitHub Releases, optional network)
    @Published var autoCheckForUpdates: Bool {
        didSet {
            Preferences.shared.autoCheckForUpdates = autoCheckForUpdates
            if autoCheckForUpdates {
                scheduleAutomaticUpdateChecks(immediate: true)
            } else {
                updateCheckTimer?.invalidate()
                updateCheckTimer = nil
            }
        }
    }

    @Published var autoInstallUpdates: Bool {
        didSet {
            Preferences.shared.autoInstallUpdates = autoInstallUpdates
            if autoInstallUpdates {
                installIfAutoUpdateEnabled()
            }
        }
    }

    @Published private(set) var updateAvailable: Bool = false
    @Published private(set) var latestRemoteVersion: String?
    @Published private(set) var releaseURL: URL?
    @Published private(set) var updateDownloadURL: URL?
    @Published private(set) var updateDownloadIsZip: Bool = true
    @Published private(set) var isCheckingUpdate: Bool = false
    @Published private(set) var isInstallingUpdate: Bool = false
    @Published private(set) var updateProgress: Double = 0
    @Published private(set) var updateCheckIdleMessage: String = ""
    @Published private(set) var updateErrorMessage: String = ""

    var appVersion: String { UpdateChecker.localVersion }
    var appBuild: String { UpdateChecker.localBuild }

    /// Throttle window for background / auto checks (manual Check always forces).
    static let updateCheckInterval: TimeInterval = 12 * 3600

    private var pollTimer: Timer?
    private var updateCheckTimer: Timer?
    private var lastAutoEjectAt: CFAbsoluteTime = 0

    private init() {
        let prefs = Preferences.shared
        isEnabled = prefs.isEnabled
        defaultDisplayID = prefs.defaultDisplayID
        currentDockDisplayID = prefs.currentDockDisplayID
        modifierKey = prefs.modifierKey
        restoreOnWake = prefs.restoreOnWake
        launchAtLogin = LaunchAtLogin.isEnabled
        blockedDisplayIDs = prefs.blockedDisplayIDs
        autoCheckForUpdates = prefs.autoCheckForUpdates
        autoInstallUpdates = prefs.autoInstallUpdates
        refresh()
        startPolling()
        scheduleAutomaticUpdateChecks(immediate: false)
    }

    private func startPolling() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            DispatchQueue.main.async { self?.syncActualDock() }
        }
        if let pollTimer {
            RunLoop.main.add(pollTimer, forMode: .common)
        }
    }

    /// Delayed first check after launch + hourly tick that only hits the network when due.
    func scheduleAutomaticUpdateChecks(immediate: Bool) {
        updateCheckTimer?.invalidate()
        guard autoCheckForUpdates else { return }

        let firstDelay: TimeInterval = immediate ? 2 : 10
        DispatchQueue.main.asyncAfter(deadline: .now() + firstDelay) { [weak self] in
            self?.checkForUpdates(force: false)
        }

        updateCheckTimer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            DispatchQueue.main.async {
                guard let self, self.autoCheckForUpdates else { return }
                self.checkForUpdates(force: false)
            }
        }
        if let updateCheckTimer {
            RunLoop.main.add(updateCheckTimer, forMode: .common)
        }
    }

    func syncActualDock() {
        // Never auto-relocate to default here except for a *blocked* host.
        // (A previous bug restored to default on every screen-geometry change.)
        if let id = PinDockEngine.shared.refreshActualDockLocation() {
            actualDockDisplayID = id
            if !blockedDisplayIDs.isEmpty, blockedDisplayIDs.contains(id) {
                let now = CFAbsoluteTimeGetCurrent()
                // Debounce; only eject from displays the user explicitly blocked.
                if now - lastAutoEjectAt > 2.0 {
                    lastAutoEjectAt = now
                    NSLog("PinDock: Dock on blocked display \(id) — Move Back to default")
                    moveBackToDefault()
                }
            }
        } else {
            actualDockDisplayID = PinDockEngine.shared.actualDockDisplayID
        }
        let host = displayHostingDock
        dockIsAway = host != 0 && defaultDisplayID != 0 && host != defaultDisplayID
        refreshStatus()
    }

    private var displayHostingDock: UInt32 {
        actualDockDisplayID != 0 ? actualDockDisplayID : currentDockDisplayID
    }

    func refresh() {
        DisplayManager.shared.refresh()
        displays = DisplayManager.shared.displays
        let live = Set(displays.map(\.id))
        blockedDisplayIDs = blockedDisplayIDs.intersection(live)
        Preferences.shared.blockedDisplayIDs = blockedDisplayIDs

        // Re-bind saved default/current via stable fingerprint (UUID/name).
        // Never silently replace a missing external default with built-in main —
        // that was wiping vertical/external defaults after login.
        rebindSavedDisplays()

        syncActualDock()
        refreshStatus()
    }

    /// Update live IDs from fingerprints. Does **not** clobber a saved external default
    /// with the built-in main just because the ID changed after login.
    private func rebindSavedDisplays() {
        let prefs = Preferences.shared
        let dm = DisplayManager.shared

        // Migrate: IDs without fingerprints → capture while still valid.
        if prefs.defaultDisplayFingerprint == nil,
           let info = dm.display(id: prefs.defaultDisplayID) {
            prefs.defaultDisplayFingerprint = DisplayFingerprint.from(display: info)
        }
        if prefs.currentDockFingerprint == nil,
           let info = dm.display(id: prefs.currentDockDisplayID) {
            prefs.currentDockFingerprint = DisplayFingerprint.from(display: info)
        }

        // --- Default ---
        let defaultMatched = DisplayIdentity.resolve(prefs.defaultDisplayFingerprint, among: displays)
            ?? (prefs.defaultDisplayID != 0 && dm.display(id: prefs.defaultDisplayID) != nil
                ? prefs.defaultDisplayID : nil)

        if let matched = defaultMatched, !blockedDisplayIDs.contains(matched) {
            if defaultDisplayID != matched {
                NSLog("PinDock: rebind default \(defaultDisplayID) → \(matched) (\(dm.name(for: matched)))")
            }
            defaultDisplayID = matched
            prefs.defaultDisplayID = matched
            if let info = dm.display(id: matched) {
                prefs.defaultDisplayFingerprint = DisplayFingerprint.from(display: info)
            }
        } else if prefs.defaultDisplayFingerprint == nil && (prefs.defaultDisplayID == 0 || dm.display(id: prefs.defaultDisplayID) == nil) {
            // True first run — pick main once and remember it.
            if let pick = displays.first(where: { !blockedDisplayIDs.contains($0.id) && $0.isMain })
                ?? displays.first(where: { !blockedDisplayIDs.contains($0.id) }) {
                prefs.setDefaultDisplay(pick)
                defaultDisplayID = pick.id
                NSLog("PinDock: first-run default → \(pick.id) “\(pick.name)”")
            }
        } else if let matched = defaultMatched, blockedDisplayIDs.contains(matched) {
            if let pick = displays.first(where: { !blockedDisplayIDs.contains($0.id) && $0.isMain })
                ?? displays.first(where: { !blockedDisplayIDs.contains($0.id) }) {
                prefs.setDefaultDisplay(pick)
                defaultDisplayID = pick.id
            }
        } else {
            // Fingerprint known but display not connected yet — keep stored preference.
            NSLog("PinDock: default “\(prefs.defaultDisplayFingerprint?.name ?? "?")” not online yet; not falling back to built-in")
        }

        // --- Current dock host ---
        let currentMatched = DisplayIdentity.resolve(prefs.currentDockFingerprint, among: displays)
            ?? (prefs.currentDockDisplayID != 0 && dm.display(id: prefs.currentDockDisplayID) != nil
                ? prefs.currentDockDisplayID : nil)
        if let matched = currentMatched {
            currentDockDisplayID = matched
            prefs.currentDockDisplayID = matched
            if let info = dm.display(id: matched) {
                prefs.currentDockFingerprint = DisplayFingerprint.from(display: info)
            }
        }
    }

    func refreshStatus() {
        isTrusted = PinDockEngine.shared.ensureAccessibility(prompt: false)
        isRunning = PinDockEngine.shared.isRunning

        let host = displayHostingDock
        dockIsAway = host != 0 && defaultDisplayID != 0 && host != defaultDisplayID

        let defName = DisplayManager.shared.name(for: defaultDisplayID)
        let hostName = DisplayManager.shared.name(for: host)

        if !isTrusted {
            statusLine = "Accessibility required — /Applications/PinDock.app"
        } else if !isEnabled {
            statusLine = "Pinning off"
        } else if isRunning {
            if dockIsAway {
                statusLine = "Dock on \(hostName) · default \(defName) · ⌘⇧D Move Back"
            } else {
                statusLine = "Default · \(defName)"
            }
        } else {
            statusLine = "Protection not running"
        }
    }

    // MARK: - Actions

    /// Set as default — status only, Dock stays put.
    func setDefaultOnly(to id: UInt32) {
        guard isAllowed(id) else { return }
        guard let info = DisplayManager.shared.display(id: id) else { return }
        defaultDisplayID = id
        Preferences.shared.setDefaultDisplay(info)
        refreshStatus()
        NSLog("PinDock: default = \(id) “\(info.name)” uuid=\(DisplayIdentity.uuidString(for: id) ?? "-") (no Dock move)")
    }

    /// Arrangement click — move Dock there automatically (default unchanged).
    func moveDockToDisplay(_ id: UInt32) {
        guard isAllowed(id) else {
            NSLog("PinDock: map click ignored — blocked \(id)")
            return
        }
        guard let info = DisplayManager.shared.display(id: id) else { return }
        NSLog("PinDock: map click → move Dock to \(id) “\(info.name)”")
        currentDockDisplayID = id
        Preferences.shared.setCurrentDockDisplay(info)
        // Delay so the mouse button is up before we warp (click must finish first).
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            PinDockEngine.shared.moveDock(to: id)
        }
        for delay in [0.35, 0.7, 1.1] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.syncActualDock()
            }
        }
    }

    /// Move Back / ⌘⇧D — automatically put Dock on the default display.
    func moveBackToDefault() {
        let id = DisplayManager.shared.resolvedAnchorID(
            preferred: defaultDisplayID,
            fingerprint: Preferences.shared.defaultDisplayFingerprint
        )
        NSLog("PinDock: Move Back → auto relocate to \(id) (default=\(defaultDisplayID) fp=\(Preferences.shared.defaultDisplayFingerprint?.name ?? "-"))")
        currentDockDisplayID = id
        if let info = DisplayManager.shared.display(id: id) {
            Preferences.shared.setCurrentDockDisplay(info)
        } else {
            Preferences.shared.currentDockDisplayID = id
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
            PinDockEngine.shared.moveDockToDefault()
        }
        for delay in [0.35, 0.7, 1.1] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.syncActualDock()
            }
        }
    }

    /// After login/wake: ensure Dock is on the resolved default (if restore is on).
    func restoreDockToDefaultIfNeeded(reason: String) {
        guard isEnabled, restoreOnWake else { return }
        DisplayManager.shared.refresh()
        rebindSavedDisplays()
        let target = DisplayManager.shared.resolvedAnchorID(
            preferred: defaultDisplayID,
            fingerprint: Preferences.shared.defaultDisplayFingerprint
        )
        guard target != 0 else { return }
        let host = PinDockEngine.shared.refreshActualDockLocation() ?? actualDockDisplayID
        if host == target {
            NSLog("PinDock: restore (\(reason)) — already on default \(target)")
            return
        }
        NSLog("PinDock: restore (\(reason)) dock \(host) → default \(target)")
        PinDockEngine.shared.moveDock(to: target)
    }

    func setAllowed(_ id: UInt32, allowed: Bool) {
        var set = blockedDisplayIDs
        if allowed {
            set.remove(id)
        } else {
            set.insert(id)
            if id == defaultDisplayID {
                if let next = displays.first(where: { $0.id != id && !set.contains($0.id) }) {
                    Preferences.shared.setDefaultDisplay(next)
                    defaultDisplayID = next.id
                }
            }
        }
        blockedDisplayIDs = set
        Preferences.shared.blockedDisplayIDs = set

        if !allowed {
            let host = displayHostingDock
            if host == id {
                moveBackToDefault()
                return
            }
        }
        refreshStatus()
    }

    func isAllowed(_ id: UInt32) -> Bool { !blockedDisplayIDs.contains(id) }

    func isActualDockHost(_ id: UInt32) -> Bool {
        actualDockDisplayID != 0 && actualDockDisplayID == id
    }

    func openAccessibility() {
        PinDockEngine.shared.ensureAccessibility(prompt: true)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            PinDockEngine.shared.restart()
            self?.refreshStatus()
        }
    }

    func retryEngine() {
        PinDockEngine.shared.ensureAccessibility(prompt: true)
        PinDockEngine.shared.restart()
        refreshStatus()
    }

    // MARK: - Updates

    /// Check GitHub Releases. Throttled to once per 12h unless `force`.
    func checkForUpdates(force: Bool = false) {
        let now = Date().timeIntervalSince1970
        if !force, now - Preferences.shared.lastUpdateCheckAt < Self.updateCheckInterval {
            // Already checked recently — still honor auto-install if we know an update exists.
            if updateAvailable {
                installIfAutoUpdateEnabled()
            }
            return
        }
        guard !isCheckingUpdate else { return }
        isCheckingUpdate = true
        updateCheckIdleMessage = ""

        UpdateChecker.checkLatest { [weak self] result in
            guard let self else { return }
            self.isCheckingUpdate = false
            Preferences.shared.lastUpdateCheckAt = Date().timeIntervalSince1970
            guard let result else {
                // Silent failure when offline
                if self.latestRemoteVersion == nil {
                    self.updateCheckIdleMessage = ""
                }
                return
            }
            self.latestRemoteVersion = result.latestVersion
            self.releaseURL = result.htmlURL
            self.updateDownloadURL = result.downloadURL
            self.updateDownloadIsZip = result.downloadIsZip
            self.updateAvailable = result.isNewer
            self.updateErrorMessage = ""
            if result.isNewer {
                self.updateCheckIdleMessage = ""
                NSLog("PinDock: update available \(UpdateChecker.localVersion) → \(result.latestVersion)")
                self.installIfAutoUpdateEnabled()
            } else {
                self.updateCheckIdleMessage = "Up to date"
            }
        }
    }

    func openReleasePage() {
        let url = releaseURL ?? UpdateChecker.releasesURL
        NSWorkspace.shared.open(url)
    }

    /// If Auto Install is on and a download URL is known, start install.
    private func installIfAutoUpdateEnabled() {
        guard autoInstallUpdates, updateAvailable, updateDownloadURL != nil, !isInstallingUpdate else { return }
        NSLog("PinDock: auto-installing update \(latestRemoteVersion ?? "?")")
        installAvailableUpdate()
    }

    /// Download the release ZIP (or DMG), replace the app, relaunch.
    func installAvailableUpdate() {
        guard updateAvailable, let url = updateDownloadURL else {
            updateErrorMessage = "No download available — open the release page instead."
            return
        }
        guard !isInstallingUpdate else { return }
        isInstallingUpdate = true
        updateProgress = 0
        updateErrorMessage = ""

        AppUpdater.install(from: url, isZip: updateDownloadIsZip, progress: { [weak self] p in
            self?.updateProgress = p
        }, completion: { [weak self] result in
            guard let self else { return }
            self.isInstallingUpdate = false
            switch result {
            case .success:
                break
            case .failure(let error):
                self.updateErrorMessage = error.localizedDescription
                NSLog("PinDock: update failed — \(error.localizedDescription)")
            }
        })
    }
}
