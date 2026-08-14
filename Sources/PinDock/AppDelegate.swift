import Cocoa
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hostingController: NSHostingController<SettingsView>?

    /// Last known display IDs — used so we only auto-restore on real plug/unplug.
    private var knownDisplayIDs: Set<UInt32> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        DisplayManager.shared.refresh()
        knownDisplayIDs = Set(DisplayManager.shared.displays.map(\.id))
        AppState.shared.refresh()

        // Maintainer helper: `PinDock --ui-preview` opens the panel as a window for screenshots.
        if CommandLine.arguments.contains("--ui-preview") {
            NSApp.setActivationPolicy(.regular)
            showUIPreviewWindow()
            return
        }

        setupStatusItem()
        setupPopover()
        registerNotifications()
        LaunchAtLogin.syncFromPreferences()

        PinDockEngine.shared.onStateChanged = { [weak self] in
            DispatchQueue.main.async {
                let prefs = Preferences.shared
                if AppState.shared.currentDockDisplayID != prefs.currentDockDisplayID {
                    AppState.shared.currentDockDisplayID = prefs.currentDockDisplayID
                }
                if AppState.shared.defaultDisplayID != prefs.defaultDisplayID {
                    AppState.shared.defaultDisplayID = prefs.defaultDisplayID
                }
                AppState.shared.syncActualDock()
                AppState.shared.refreshStatus()
                self?.updateStatusIcon()
            }
        }

        if Preferences.shared.isEnabled {
            PinDockEngine.shared.start()
            scheduleLoginRestore()
        }

        updateStatusIcon()
        // Do not auto-open panel on launch — Control Center style: user opens it.
    }

    /// Borderless floating window with the real SettingsView (for README screenshots).
    private var previewWindow: NSWindow?

    private func showUIPreviewWindow() {
        let root = SettingsView(state: AppState.shared)
            .frame(width: 360, height: 520)
        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = NSRect(x: 0, y: 0, width: 360, height: 520)

        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 520),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "PinDock"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: 360, height: 520))
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        previewWindow = window
        NSLog("PinDock: UI preview window open (for screenshots)")
    }

    private func scheduleLoginRestore() {
        guard Preferences.shared.restoreOnWake else { return }
        for delay in [1.5, 4.0, 8.0] as [TimeInterval] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard Preferences.shared.isEnabled, Preferences.shared.restoreOnWake else { return }
                AppState.shared.refresh()
                AppState.shared.restoreDockToDefaultIfNeeded(reason: "login+\(delay)s")
                self?.knownDisplayIDs = Set(DisplayManager.shared.displays.map(\.id))
                self?.updateStatusIcon()
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        PinDockEngine.shared.stop()
        popover?.performClose(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        togglePopover()
        return true
    }

    // MARK: - Status item

    private func setupStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.image = StatusBarIcon.image(active: Preferences.shared.isEnabled)
            button.imagePosition = .imageOnly
            button.toolTip = "PinDock"
            button.target = self
            button.action = #selector(statusItemClicked(_:))
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
    }

    private func updateStatusIcon() {
        let active = Preferences.shared.isEnabled && PinDockEngine.shared.isRunning
        statusItem?.button?.image = StatusBarIcon.image(active: active)
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else {
            togglePopover()
            return
        }
        if event.type == .rightMouseUp {
            showContextMenu()
        } else {
            togglePopover()
        }
    }

    private func showContextMenu() {
        // Close popover so it doesn't fight the menu.
        popover?.performClose(nil)

        let menu = NSMenu()
        let openItem = NSMenuItem(title: "Open PinDock…", action: #selector(openPanelAction), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)
        menu.addItem(.separator())
        let relocate = NSMenuItem(title: "Move Back to Default", action: #selector(relocateAction), keyEquivalent: "d")
        relocate.keyEquivalentModifierMask = [.command, .shift]
        relocate.target = self
        menu.addItem(relocate)
        menu.addItem(.separator())
        let quit = NSMenuItem(title: "Quit PinDock", action: #selector(quitAction), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        statusItem?.menu = menu
        statusItem?.button?.performClick(nil)
        DispatchQueue.main.async { [weak self] in
            self?.statusItem?.menu = nil
        }
    }

    // MARK: - Control-Center-style popover

    private func setupPopover() {
        let root = SettingsView(state: AppState.shared)
        let hosting = NSHostingController(rootView: root)
        hostingController = hosting

        let pop = NSPopover()
        pop.contentViewController = hosting
        pop.behavior = .transient // click outside / Escape dismisses
        pop.animates = true
        pop.delegate = self
        // Semitransparent system chrome — materials in the SwiftUI view show through.
        pop.appearance = NSAppearance(named: .vibrantDark)
            ?? NSAppearance(named: .aqua)
        popover = pop
    }

    private func togglePopover() {
        guard let popover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(relativeTo: button)
        }
    }

    private func showPopover(relativeTo button: NSStatusBarButton) {
        AppState.shared.refresh()
        AppState.shared.checkForUpdates(force: false)

        // Adaptive appearance (light/dark)
        if let appearance = NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) {
            popover?.appearance = NSAppearance(named: appearance == .darkAqua ? .vibrantDark : .vibrantLight)
        }

        // Content size matches SettingsView ideal size
        popover?.contentSize = NSSize(width: 360, height: 520)

        NSApp.activate(ignoringOtherApps: true)
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)

        // Keep popover key for Escape / text focus
        popover?.contentViewController?.view.window?.makeKey()
    }

    @objc private func openPanelAction() { togglePopover() }

    @objc private func relocateAction() {
        AppState.shared.moveBackToDefault()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        AppState.shared.refresh()
    }

    func popoverDidClose(_ notification: Notification) {
        // nothing sticky
    }

    // MARK: - Notifications

    private func registerNotifications() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(onWake),
            name: NSWorkspace.didWakeNotification,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func onWake() {
        guard Preferences.shared.isEnabled, Preferences.shared.restoreOnWake else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            AppState.shared.refresh()
            AppState.shared.restoreDockToDefaultIfNeeded(reason: "wake")
            self.knownDisplayIDs = Set(DisplayManager.shared.displays.map(\.id))
            self.updateStatusIcon()
        }
    }

    @objc private func onScreenChange() {
        DispatchQueue.main.async {
            DisplayManager.shared.refresh()
            let currentIDs = Set(DisplayManager.shared.displays.map(\.id))
            let previousIDs = self.knownDisplayIDs
            let topologyChanged = !previousIDs.isEmpty && previousIDs != currentIDs
            self.knownDisplayIDs = currentIDs

            AppState.shared.refresh()
            self.updateStatusIcon()

            guard topologyChanged,
                  Preferences.shared.isEnabled,
                  Preferences.shared.restoreOnWake else { return }

            NSLog("PinDock: display topology changed \(previousIDs) → \(currentIDs); restore to default")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                AppState.shared.refresh()
                AppState.shared.restoreDockToDefaultIfNeeded(reason: "topology")
            }
        }
    }
}

// MARK: - Custom status bar icon

enum StatusBarIcon {
    static func image(active: Bool) -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { _ in
            let alpha: CGFloat = active ? 1.0 : 0.45

            let head = NSBezierPath(ovalIn: NSRect(x: 6.5, y: 10.5, width: 5, height: 5))
            NSColor.black.withAlphaComponent(alpha).setFill()
            head.fill()

            let stem = NSBezierPath()
            stem.move(to: NSPoint(x: 9, y: 10.5))
            stem.line(to: NSPoint(x: 9, y: 5.5))
            stem.lineWidth = 1.6
            stem.lineCapStyle = .round
            NSColor.black.withAlphaComponent(alpha).setStroke()
            stem.stroke()

            let bar = NSBezierPath(
                roundedRect: NSRect(x: 2, y: 1.5, width: 14, height: 3.2),
                xRadius: 1.4, yRadius: 1.4
            )
            NSColor.black.withAlphaComponent(alpha).setFill()
            bar.fill()

            return true
        }
        image.isTemplate = true
        return image
    }
}
