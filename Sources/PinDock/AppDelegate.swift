import Cocoa
import SwiftUI
import ApplicationServices

final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate, NSWindowDelegate {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private var hostingController: NSHostingController<SettingsView>?
    private var mainWindow: NSWindow?
    private var popoverLocalClickMonitor: Any?
    private var popoverGlobalClickMonitor: Any?

    /// Last known display IDs — used so we only auto-restore on real plug/unplug.
    private var knownDisplayIDs: Set<UInt32> = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        Preferences.shared.appColorScheme.apply()
        applyActivationPolicy(Preferences.shared.appPresentation)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        DisplayManager.shared.refresh()
        knownDisplayIDs = Set(DisplayManager.shared.displays.map(\.id))
        AppState.shared.refresh()

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

        // Maintainer helper: `PinDock --ui-preview` opens the panel as a window for screenshots.
        // Engine is started above so the UI matches a real session (no false banners).
        if CommandLine.arguments.contains("--ui-preview") {
            NSApp.setActivationPolicy(.regular)
            AppState.shared.refresh()
            showUIPreviewWindow()
            return
        }

        registerNotifications()
        LaunchAtLogin.syncFromPreferences()
        let mode = Preferences.shared.appPresentation
        // Window / both: show the app only when the user opened us (Dock, Spotlight, Finder).
        // Login item and menu-bar-only stay in the background.
        applyPresentation(mode, revealWindow: mode.showsWindow && !Self.launchedAsLoginItem())

        updateStatusIcon()
    }

    /// Borderless floating window with the real SettingsView (for README screenshots).
    private var previewWindow: NSWindow?

    private func showUIPreviewWindow() {
        let panelW: CGFloat = SettingsView.compactPanelSize.width
        let panelH: CGFloat = 680
        let root = SettingsView(state: AppState.shared)
            .frame(width: panelW, height: panelH)
        let hosting = NSHostingController(rootView: root)
        hosting.view.frame = NSRect(x: 0, y: 0, width: panelW, height: panelH)

        // Borderless panel so screenshots match the real menu-bar popover (no traffic lights).
        let window = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: panelW, height: panelH),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        window.title = "PinDock"
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.contentViewController = hosting
        window.setContentSize(NSSize(width: panelW, height: panelH))
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
        removePopoverDismissMonitors()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Dock / Spotlight / Finder — only when PinDock is an app (not menu-bar-only).
        if Preferences.shared.appPresentation.showsWindow {
            showMainWindow()
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Utility stays running (engine + optional menu bar) when the window is closed.
        false
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    func windowDidBecomeKey(_ notification: Notification) {
        guard (notification.object as? NSWindow) === mainWindow else { return }
        popover?.performClose(nil)
    }

    func applicationDidResignActive(_ notification: Notification) {
        popover?.performClose(nil)
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

    // MARK: - Menu-bar popover (arrow + pop animation, does not activate the app)

    private func setupPopover() {
        let hosting = NSHostingController(rootView: SettingsView(state: AppState.shared))
        hostingController = hosting

        let pop = NSPopover()
        pop.contentViewController = hosting
        pop.contentSize = SettingsView.compactPanelSize
        // applicationDefined: .transient closes itself when PinDock is not the active app.
        pop.behavior = .applicationDefined
        pop.animates = true
        pop.delegate = self
        pop.appearance = NSApp.effectiveAppearance
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

        popover?.appearance = NSApp.effectiveAppearance
        popover?.contentSize = SettingsView.compactPanelSize
        // Do not NSApp.activate — that pulls PinDock to the foreground.
        popover?.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        preparePopoverWindow()
        installPopoverDismissMonitors()
    }

    /// Keep the system bubble + arrow. Don’t steal key/activation from the front app.
    /// Restyle popover chrome to the same behind-window glass as the app (not the dark `.popover` material).
    private func preparePopoverWindow() {
        guard let view = popover?.contentViewController?.view else { return }
        view.appearance = NSApp.effectiveAppearance
        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor.clear.cgColor
        guard let window = view.window else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.appearance = NSApp.effectiveAppearance
        if let panel = window as? NSPanel {
            panel.hidesOnDeactivate = false
            panel.becomesKeyOnlyIfNeeded = false
            panel.styleMask.insert(.nonactivatingPanel)
            // Key window → switches draw blue. nonactivatingPanel → app stays behind.
            panel.makeKey()
        }
        matchPopoverChrome(hostingView: view, in: window)
    }

    private func matchPopoverChrome(hostingView: NSView, in window: NSWindow) {
        func restyle(_ view: NSView) {
            if view === hostingView { return }
            if let effect = view as? NSVisualEffectView {
                effect.material = .underWindowBackground
                effect.blendingMode = .behindWindow
                effect.state = .active
                effect.isEmphasized = true
            }
            for sub in view.subviews where sub !== hostingView {
                restyle(sub)
            }
        }
        if let root = window.contentView?.superview ?? window.contentView {
            restyle(root)
        }
    }

    private static func launchedAsLoginItem() -> Bool {
        let launchedAsLogin: AEKeyword = 0x6C676974 // 'lgit'
        guard let event = NSAppleEventManager.shared().currentAppleEvent else { return false }
        return event.attributeDescriptor(forKeyword: launchedAsLogin)?.booleanValue == true
    }

    private func installPopoverDismissMonitors() {
        removePopoverDismissMonitors()
        popoverLocalClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] event in
            self?.dismissPopoverIfClickOutside(event)
            return event
        }
        popoverGlobalClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            DispatchQueue.main.async { self?.popover?.performClose(nil) }
        }
    }

    private func removePopoverDismissMonitors() {
        if let popoverLocalClickMonitor {
            NSEvent.removeMonitor(popoverLocalClickMonitor)
            self.popoverLocalClickMonitor = nil
        }
        if let popoverGlobalClickMonitor {
            NSEvent.removeMonitor(popoverGlobalClickMonitor)
            self.popoverGlobalClickMonitor = nil
        }
    }

    private func dismissPopoverIfClickOutside(_ event: NSEvent) {
        guard popover?.isShown == true else { return }
        if event.window === popover?.contentViewController?.view.window { return }
        if let button = statusItem?.button, event.window === button.window {
            let loc = button.convert(event.locationInWindow, from: nil)
            if button.bounds.contains(loc) { return }
        }
        popover?.performClose(nil)
    }

    @objc private func openPanelAction() {
        let mode = Preferences.shared.appPresentation
        if mode.showsWindow {
            showMainWindow()
        } else {
            togglePopover()
        }
    }

    @objc private func relocateAction() {
        AppState.shared.moveBackToDefault()
    }

    @objc private func quitAction() {
        NSApp.terminate(nil)
    }

    // MARK: - NSPopoverDelegate

    func popoverDidShow(_ notification: Notification) {
        preparePopoverWindow()
    }

    func popoverDidClose(_ notification: Notification) {
        removePopoverDismissMonitors()
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
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onPresentationChange(_:)),
            name: .pindockPresentationDidChange,
            object: nil
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(onColorSchemeChange),
            name: .pindockColorSchemeDidChange,
            object: nil
        )
    }

    @objc private func onColorSchemeChange() {
        let appearance = NSApp.effectiveAppearance
        popover?.appearance = appearance
        if popover?.isShown == true {
            preparePopoverWindow()
        }
        mainWindow?.appearance = NSApp.appearance
    }

    @objc private func onPresentationChange(_ notification: Notification) {
        let mode = (notification.object as? AppPresentation) ?? Preferences.shared.appPresentation
        applyPresentation(mode, revealWindow: mode.showsWindow)
    }

    // MARK: - Presentation (menu bar / window / both)

    private func applyActivationPolicy(_ mode: AppPresentation) {
        NSApp.setActivationPolicy(mode.activationPolicy)
    }

    private func applyPresentation(_ mode: AppPresentation, revealWindow: Bool) {
        applyActivationPolicy(mode)

        if mode.showsMenuBar {
            if statusItem == nil { setupStatusItem() }
            if popover == nil { setupPopover() }
            updateStatusIcon()
        } else {
            popover?.performClose(nil)
            if let item = statusItem {
                NSStatusBar.system.removeStatusItem(item)
                statusItem = nil
            }
            popover = nil
            hostingController = nil
        }

        if mode.showsWindow {
            if revealWindow {
                showMainWindow()
            }
        } else {
            mainWindow?.orderOut(nil)
        }
    }

    private func showMainWindow() {
        if mainWindow == nil {
            mainWindow = makeMainWindow()
        }
        AppState.shared.refresh()
        if AppState.shared.autoCheckForUpdates {
            AppState.shared.checkForUpdates(force: false)
        }
        guard let window = mainWindow else { return }
        ensureComfortableWindowFrame(window)
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private static let defaultWindowSize = NSSize(width: 920, height: 640)
    private static let minWindowSize = NSSize(width: 560, height: 400)

    private func makeMainWindow() -> NSWindow {
        let hosting = NSHostingController(rootView: SettingsView(state: AppState.shared, compact: false))
        // Do not let SwiftUI shrink the window to the compact popover’s intrinsic size.
        hosting.sizingOptions = []

        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.defaultWindowSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "PinDock"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbarStyle = .unified
        window.isOpaque = false
        window.backgroundColor = .clear
        window.isReleasedWhenClosed = false
        window.contentViewController = hosting
        window.contentMinSize = NSSize(width: 560, height: 400)
        window.setContentSize(Self.defaultWindowSize)
        window.delegate = self
        window.center()
        window.setFrameAutosaveName("PinDockMainWindow.v11")
        ensureComfortableWindowFrame(window)
        return window
    }

    /// Autosave / SwiftUI can leave a tiny frame; bump back to a usable size.
    private func ensureComfortableWindowFrame(_ window: NSWindow) {
        let frame = window.frame
        let tooSmall = frame.width < Self.minWindowSize.width - 1
            || frame.height < Self.minWindowSize.height - 1
        if tooSmall {
            var next = frame
            next.size = Self.defaultWindowSize
            if let screen = window.screen ?? NSScreen.main {
                let vis = screen.visibleFrame
                next.size.width = min(next.size.width, vis.width - 40)
                next.size.height = min(next.size.height, vis.height - 40)
                next.origin.x = vis.midX - next.size.width / 2
                next.origin.y = vis.midY - next.size.height / 2
            }
            window.setFrame(next, display: true)
        }
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
