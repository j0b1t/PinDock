import Cocoa
import ApplicationServices
import CoreGraphics

/// Dock lock + automatic relocate.
///
/// - Protection: soft-block bottom edges except the current Dock host.
/// - Modifier held: allowed displays open for a *native* Dock move; release = lock again.
/// - Move Back / map / restore: automatic relocate (brief cursor trip, then restore).
final class PinDockEngine {
    static let shared = PinDockEngine()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?

    private var lastUINotify: CFAbsoluteTime = 0
    private var lastPointerY: CGFloat = -1
    private var lastDockPoll: CFAbsoluteTime = 0
    private var lastRelocateAt: CFAbsoluteTime = 0

    /// While true / tap disabled, protection never clamps.
    private var suppressProtection = false
    private var relocateInFlight = false

    private(set) var isTrusted = false
    private(set) var isRunning = false
    private(set) var actualDockDisplayID: CGDirectDisplayID = 0

    var isAcquiring: Bool { false }
    var acquiringDisplayID: CGDirectDisplayID { 0 }
    var isBusy: Bool { relocateInFlight }

    var onStateChanged: (() -> Void)?

    private init() {}

    // MARK: Accessibility

    @discardableResult
    func ensureAccessibility(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        isTrusted = AXIsProcessTrustedWithOptions(opts)
        return isTrusted
    }

    // MARK: Lifecycle

    func start() {
        guard Preferences.shared.isEnabled else {
            stop()
            return
        }
        guard ensureAccessibility(prompt: true) else {
            stop()
            onStateChanged?()
            return
        }
        if isRunning { stop() }

        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.flagsChanged.rawValue) |
            (1 << CGEventType.tapDisabledByTimeout.rawValue) |
            (1 << CGEventType.tapDisabledByUserInput.rawValue)

        let cb: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let eng = Unmanaged<PinDockEngine>.fromOpaque(refcon).takeUnretainedValue()
            return eng.handle(event: event, type: type)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: cb,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isTrusted = false
            onStateChanged?()
            return
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let src = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        isRunning = true
        installMoveBackHotkey()
        refreshActualDockLocation()
        onStateChanged?()
    }

    func stop() {
        if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let src = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), src, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        removeMoveBackHotkey()
        suppressProtection = false
        relocateInFlight = false
        isRunning = false
        onStateChanged?()
    }

    func restart() {
        stop()
        if Preferences.shared.isEnabled { start() }
    }

    func canHostDock(_ id: CGDirectDisplayID) -> Bool {
        Preferences.shared.isAllowed(id)
    }

    // MARK: - Hotkey ⌘⇧D = Move Back (automatic)

    private func installMoveBackHotkey() {
        removeMoveBackHotkey()
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] e in
            _ = self?.handleMoveBackHotkey(e)
        }
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if self?.handleMoveBackHotkey(e) == true { return nil }
            return e
        }
    }

    private func removeMoveBackHotkey() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let localKeyMonitor { NSEvent.removeMonitor(localKeyMonitor) }
        keyMonitor = nil
        localKeyMonitor = nil
    }

    @discardableResult
    private func handleMoveBackHotkey(_ event: NSEvent) -> Bool {
        let mods = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        // Require ⌘ and ⇧; extra modifiers (⌃ etc.) still OK — users often hold more keys.
        guard mods.contains(.command), mods.contains(.shift) else { return false }
        let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
        let isD = key == "d" || event.keyCode == 2 // kVK_ANSI_D
        let isDelete = event.keyCode == 51 || event.keyCode == 117
        guard isD || isDelete else { return false }
        NSLog("PinDock: hotkey ⌘⇧D → Move Back")
        DispatchQueue.main.async {
            AppState.shared.moveBackToDefault()
        }
        return true
    }

    // MARK: - Dock location

    @discardableResult
    func refreshActualDockLocation() -> CGDirectDisplayID? {
        guard let id = DockLocator.displayIDHostingDock() else { return nil }
        if actualDockDisplayID != id {
            actualDockDisplayID = id
            if canHostDock(id), let info = DisplayManager.shared.display(id: id) {
                Preferences.shared.setCurrentDockDisplay(info)
            }
            notifyUI()
        } else {
            actualDockDisplayID = id
        }
        return id
    }

    // MARK: - Event tap (protection + modifier only)

    private func handle(event: CGEvent, type: CGEventType) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return Unmanaged.passUnretained(event)
        }
        if suppressProtection || !Preferences.shared.isEnabled || relocateInFlight {
            return Unmanaged.passUnretained(event)
        }
        if type == .flagsChanged {
            return Unmanaged.passUnretained(event)
        }

        let t = CFAbsoluteTimeGetCurrent()
        if t - lastDockPoll > 1.5 {
            lastDockPoll = t
            refreshActualDockLocation()
        }

        let loc = event.location
        DisplayManager.shared.refreshIfNeeded()
        guard let display = DisplayManager.shared.displayContaining(quartzPoint: loc) else {
            lastPointerY = loc.y
            return Unmanaged.passUnretained(event)
        }

        let prefs = Preferences.shared
        let dockHost: CGDirectDisplayID = {
            if actualDockDisplayID != 0 { return actualDockDisplayID }
            return DisplayManager.shared.resolvedAnchorID(
                preferred: prefs.currentDockDisplayID,
                fingerprint: prefs.currentDockFingerprint
            )
        }()

        let zone: CGFloat = 3
        let frame = display.quartzFrame
        let distBottom = frame.maxY - loc.y
        let atBottom = distBottom >= -1 && distBottom <= zone
        let blocked = !canHostDock(display.id)
        let movingUp = lastPointerY >= 0 && loc.y < lastPointerY - 0.4
        lastPointerY = loc.y

        if movingUp {
            return Unmanaged.passUnretained(event)
        }

        let modifier = isModifierHeld(in: event)

        if blocked {
            if atBottom { return softBlockBottom(event, frame: frame, zone: 5) }
            return Unmanaged.passUnretained(event)
        }

        // Open only while modifier is held, or on the display that already has the Dock.
        if display.id == dockHost || modifier {
            if atBottom, modifier, let info = DisplayManager.shared.display(id: display.id) {
                prefs.setCurrentDockDisplay(info)
            }
            return Unmanaged.passUnretained(event)
        }

        if atBottom {
            return softBlockBottom(event, frame: frame, zone: zone)
        }
        return Unmanaged.passUnretained(event)
    }

    private func softBlockBottom(_ event: CGEvent, frame: CGRect, zone: CGFloat) -> Unmanaged<CGEvent>? {
        let safeY = frame.maxY - zone - 1
        let loc = event.location
        guard loc.y > safeY else { return Unmanaged.passUnretained(event) }
        event.location = CGPoint(x: loc.x, y: safeY)
        return Unmanaged.passUnretained(event)
    }

    private func isModifierHeld(in event: CGEvent) -> Bool {
        guard let flag = Preferences.shared.modifierKey.eventFlag else { return false }
        if event.flags.contains(flag) { return true }
        return CGEventSource.flagsState(.hidSystemState).contains(flag)
    }

    private func notifyUI() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastUINotify < 0.12 { return }
        lastUINotify = now
        DispatchQueue.main.async { [weak self] in self?.onStateChanged?() }
    }

    // MARK: - Automatic Dock relocate

    func moveDock(to displayID: CGDirectDisplayID) {
        NSLog("PinDock: moveDock(to: \(displayID))")
        relocate(to: displayID)
    }

    func moveDockToDefault() {
        DisplayManager.shared.refresh()
        let id = DisplayManager.shared.resolvedAnchorID(
            preferred: Preferences.shared.defaultDisplayID,
            fingerprint: Preferences.shared.defaultDisplayFingerprint
        )
        NSLog("PinDock: moveDockToDefault → \(id) (fp=\(Preferences.shared.defaultDisplayFingerprint?.name ?? "-"))")
        relocate(to: id)
    }

    func relocateDockToDefault(restoreCursor: Bool = true) { moveDockToDefault() }
    func relocateDockToAnchor(restoreCursor: Bool = true) { moveDockToDefault() }
    func relocateDock(to displayID: CGDirectDisplayID, makeDefault: Bool = false, force: Bool = false) {
        if makeDefault { Preferences.shared.defaultDisplayID = displayID }
        relocate(to: displayID)
    }

    func ejectDockIfOnBlockedDisplay() {
        refreshActualDockLocation()
        let host = actualDockDisplayID
        guard host != 0, !canHostDock(host) else { return }
        moveDockToDefault()
    }

    private func relocate(to displayID: CGDirectDisplayID) {
        if relocateInFlight {
            NSLog("PinDock: relocate skipped (in flight)")
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        if now - lastRelocateAt < 0.25 {
            NSLog("PinDock: relocate skipped (debounce)")
            return
        }

        guard canHostDock(displayID) else {
            NSLog("PinDock: relocate ignored — blocked \(displayID)")
            return
        }
        guard ensureAccessibility(prompt: false) else {
            NSLog("PinDock: relocate needs Accessibility")
            DispatchQueue.main.async {
                let a = NSAlert()
                a.messageText = "Accessibility required"
                a.informativeText = "Enable PinDock in System Settings → Privacy & Security → Accessibility (/Applications/PinDock.app)."
                a.runModal()
            }
            return
        }

        if Thread.isMainThread {
            performRelocate(to: displayID)
        } else {
            DispatchQueue.main.async { [weak self] in
                self?.performRelocate(to: displayID)
            }
        }
    }

    private func performRelocate(to displayID: CGDirectDisplayID) {
        relocateInFlight = true
        lastRelocateAt = CFAbsoluteTimeGetCurrent()
        suppressProtection = true

        // Fully disable the tap so synthetic edge hits are never soft-blocked.
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }

        defer {
            suppressProtection = false
            relocateInFlight = false
            if isRunning, let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            notifyUI()
        }

        DisplayManager.shared.refresh()
        guard let info = DisplayManager.shared.display(id: displayID),
              let screen = nsScreen(for: displayID) else {
            NSLog("PinDock: relocate — unknown display \(displayID)")
            return
        }

        // Never early-out on DockLocator — it is often wrong during transitions.
        // Explicit user action always performs an edge hit.

        let orientation = dockOrientation()
        let saved = DisplayManager.currentPointerQuartz()
        let before = DockLocator.displayIDHostingDock() ?? 0
        NSLog("PinDock: auto-relocate → \(displayID) (\(info.name)) orient=\(orientation) before=\(before) cursor=\(saved)")

        // Release any in-progress click (map / button) before warping.
        spin(0.03)

        var success = hitDockEdge(screen: screen, displayID: displayID, orientation: orientation, dwell: 0.22)
        if !success {
            NSLog("PinDock: first edge hit failed — longer dwell")
            success = hitDockEdge(screen: screen, displayID: displayID, orientation: orientation, dwell: 0.40)
        }

        // Restore cursor — never leave it parked on the edge.
        setCursor(saved)
        spin(0.02)

        if let info = DisplayManager.shared.display(id: displayID) {
            Preferences.shared.setCurrentDockDisplay(info)
        } else {
            Preferences.shared.currentDockDisplayID = displayID
        }
        if let host = DockLocator.displayIDHostingDock() {
            actualDockDisplayID = host
            if canHostDock(host), let info = DisplayManager.shared.display(id: host) {
                Preferences.shared.setCurrentDockDisplay(info)
            }
            NSLog("PinDock: relocate done host=\(host) wanted=\(displayID) ok=\(host == displayID)")
        } else {
            // Locator failed (e.g. auto-hide) — trust the request.
            actualDockDisplayID = displayID
            NSLog("PinDock: relocate done (locator nil) assumed \(displayID)")
        }
    }

    /// Drive the pointer into the Dock edge so macOS moves the Dock natively.
    /// Uses NSScreen Cocoa frames → Quartz via DisplayManager (matches real mouse events).
    @discardableResult
    private func hitDockEdge(
        screen: NSScreen,
        displayID: CGDirectDisplayID,
        orientation: String,
        dwell: TimeInterval
    ) -> Bool {
        let f = screen.frame // Cocoa: origin bottom-left

        // Cocoa points: approach inside the display, then into the Dock edge.
        let cocoaCenter = CGPoint(x: f.midX, y: f.midY)
        let cocoaApproach: CGPoint
        let cocoaEdge: CGPoint
        switch orientation {
        case "left":
            cocoaApproach = CGPoint(x: f.minX + 60, y: f.midY)
            cocoaEdge = CGPoint(x: f.minX + 1, y: f.midY)
        case "right":
            cocoaApproach = CGPoint(x: f.maxX - 60, y: f.midY)
            cocoaEdge = CGPoint(x: f.maxX - 1, y: f.midY)
        default: // bottom
            cocoaApproach = CGPoint(x: f.midX, y: f.minY + 64)
            cocoaEdge = CGPoint(x: f.midX, y: f.minY + 1)
        }

        let dm = DisplayManager.shared
        let qCenter = dm.quartzPoint(fromCocoa: cocoaCenter)
        let qApproach = dm.quartzPoint(fromCocoa: cocoaApproach)
        let qEdge = dm.quartzPoint(fromCocoa: cocoaEdge)

        // 0) Jump to center of target first (helps multi-monitor Dock handoff).
        setCursor(qCenter)
        spin(0.025)

        // 1) Approach
        setCursor(qApproach)
        spin(0.02)

        // 2) Step into the edge (motion into the boundary is what Dock notices).
        let steps = 8
        for i in 1...steps {
            let t = CGFloat(i) / CGFloat(steps)
            let p = CGPoint(
                x: qApproach.x + (qEdge.x - qApproach.x) * t,
                y: qApproach.y + (qEdge.y - qApproach.y) * t
            )
            setCursor(p)
            spin(0.01)
        }

        // 3) Hard edge via display-local API as well.
        let bounds = CGDisplayBounds(displayID)
        let localEdge: CGPoint
        switch orientation {
        case "left":
            localEdge = CGPoint(x: 0, y: bounds.height / 2)
        case "right":
            localEdge = CGPoint(x: max(bounds.width - 1, 0), y: bounds.height / 2)
        default:
            localEdge = CGPoint(x: bounds.width / 2, y: max(bounds.height - 1, 0))
        }
        CGDisplayMoveCursorToPoint(displayID, localEdge)
        setCursor(qEdge)
        spin(0.03)

        // 4) Dwell + wiggle along the edge.
        let end = CFAbsoluteTimeGetCurrent() + dwell
        var flip = false
        while CFAbsoluteTimeGetCurrent() < end {
            flip.toggle()
            let d: CGFloat = flip ? 14 : -14
            let cocoaWiggle: CGPoint
            switch orientation {
            case "left", "right":
                cocoaWiggle = CGPoint(x: cocoaEdge.x, y: cocoaEdge.y + d)
            default:
                cocoaWiggle = CGPoint(x: cocoaEdge.x + d, y: cocoaEdge.y)
            }
            let qWiggle = dm.quartzPoint(fromCocoa: cocoaWiggle)
            setCursor(qWiggle)
            // Also re-pin to absolute edge each tick.
            CGDisplayMoveCursorToPoint(displayID, localEdge)
            spin(0.02)
            if let host = DockLocator.displayIDHostingDock(), host == displayID {
                return true
            }
        }

        return DockLocator.displayIDHostingDock() == displayID
    }

    private func nsScreen(for displayID: CGDirectDisplayID) -> NSScreen? {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            if CGDirectDisplayID(number.uint32Value) == displayID {
                return screen
            }
        }
        return nil
    }

    private func setCursor(_ quartzPoint: CGPoint) {
        // Keep association on — dock reacts more reliably to a “real” cursor.
        CGWarpMouseCursorPosition(quartzPoint)
        postMouseMoved(quartzPoint)
    }

    private func postMouseMoved(_ quartzPoint: CGPoint) {
        let source = CGEventSource(stateID: .hidSystemState)
        source?.localEventsSuppressionInterval = 0
        if let e = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: quartzPoint,
            mouseButton: .left
        ) {
            e.post(tap: .cghidEventTap)
        }
        // Session tap as well — some macOS versions only deliver one of them to Dock.
        if let e2 = CGEvent(
            mouseEventSource: source,
            mouseType: .mouseMoved,
            mouseCursorPosition: quartzPoint,
            mouseButton: .left
        ) {
            e2.post(tap: .cgSessionEventTap)
        }
    }

    private func dockOrientation() -> String {
        if let o = UserDefaults(suiteName: "com.apple.dock")?.string(forKey: "orientation") {
            return o
        }
        return "bottom"
    }

    private func spin(_ seconds: TimeInterval) {
        let end = CFAbsoluteTimeGetCurrent() + seconds
        while CFAbsoluteTimeGetCurrent() < end {
            RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 0.002))
        }
    }
}
