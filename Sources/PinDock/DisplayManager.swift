import Cocoa
import CoreGraphics

struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    /// Quartz global bounds (origin top-left of main display, Y grows downward).
    let quartzFrame: CGRect
    /// Cocoa global frame (origin bottom-left of primary, Y grows upward).
    let cocoaFrame: CGRect
    let isMain: Bool
    let isBuiltin: Bool

    var menuTitle: String {
        var parts: [String] = [name]
        if isMain { parts.append("(Main)") }
        if isBuiltin { parts.append("(Built-in)") }
        let w = Int(cocoaFrame.width)
        let h = Int(cocoaFrame.height)
        parts.append("\(w)×\(h)")
        return parts.joined(separator: " ")
    }
}

final class DisplayManager {
    static let shared = DisplayManager()
    private static var lastRefresh: CFAbsoluteTime = 0

    private(set) var displays: [DisplayInfo] = []

    private init() {
        refresh()
    }

    func refresh() {
        var result: [DisplayInfo] = []
        let mainID = CGMainDisplayID()

        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let displayID = CGDirectDisplayID(number.uint32Value)
            let name = screen.localizedName
            let isBuiltin = CGDisplayIsBuiltin(displayID) != 0
            let isMain = displayID == mainID || screen == NSScreen.main
            let quartzFrame = CGDisplayBounds(displayID)

            result.append(
                DisplayInfo(
                    id: displayID,
                    name: name,
                    quartzFrame: quartzFrame,
                    cocoaFrame: screen.frame,
                    isMain: isMain,
                    isBuiltin: isBuiltin
                )
            )
        }

        result.sort { lhs, rhs in
            if lhs.isMain != rhs.isMain { return lhs.isMain }
            return lhs.cocoaFrame.minX < rhs.cocoaFrame.minX
        }

        displays = result
        Self.lastRefresh = CFAbsoluteTimeGetCurrent()
    }

    func refreshIfNeeded() {
        let now = CFAbsoluteTimeGetCurrent()
        if now - Self.lastRefresh > 1.0 {
            refresh()
        }
    }

    func display(id: CGDirectDisplayID) -> DisplayInfo? {
        displays.first { $0.id == id }
    }

    /// Hit-test using Quartz coordinates (CGEvent.location / CGWarpMouseCursorPosition).
    func displayContaining(quartzPoint point: CGPoint) -> DisplayInfo? {
        for display in displays {
            // Inset slightly so edge points still hit.
            if display.quartzFrame.insetBy(dx: -2, dy: -2).contains(point) {
                return display
            }
        }
        var best: DisplayInfo?
        var bestDistance = CGFloat.greatestFiniteMagnitude
        for display in displays {
            let f = display.quartzFrame
            let dx: CGFloat
            if point.x < f.minX { dx = f.minX - point.x }
            else if point.x > f.maxX { dx = point.x - f.maxX }
            else { dx = 0 }
            let dy: CGFloat
            if point.y < f.minY { dy = f.minY - point.y }
            else if point.y > f.maxY { dy = point.y - f.maxY }
            else { dy = 0 }
            let d = dx * dx + dy * dy
            if d < bestDistance {
                bestDistance = d
                best = display
            }
        }
        return best
    }

    /// Resolve a preferred display ID using an optional stable fingerprint first.
    func resolvedAnchorID(
        preferred: CGDirectDisplayID,
        fingerprint: DisplayFingerprint? = nil
    ) -> CGDirectDisplayID {
        if let resolved = DisplayIdentity.resolve(fingerprint, among: displays) {
            return resolved
        }
        if preferred != 0, display(id: preferred) != nil {
            return preferred
        }
        if let main = displays.first(where: { $0.isMain }) {
            return main.id
        }
        return displays.first?.id ?? 0
    }

    func name(for id: CGDirectDisplayID) -> String {
        display(id: id)?.name ?? "Display \(id)"
    }

    /// Current pointer in Quartz coords (same space as CGWarpMouseCursorPosition).
    static func currentPointerQuartz() -> CGPoint {
        if let e = CGEvent(source: nil) {
            return e.location
        }
        return DisplayManager.shared.quartzPoint(fromCocoa: NSEvent.mouseLocation)
    }

    /// Robust Cocoa → Quartz for multi-monitor setups.
    func quartzPoint(fromCocoa cocoa: CGPoint) -> CGPoint {
        for screen in NSScreen.screens {
            // Expand a bit so points on the edge still match.
            if screen.frame.insetBy(dx: -1, dy: -1).contains(cocoa) {
                guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                    continue
                }
                let displayID = CGDirectDisplayID(number.uint32Value)
                let bounds = CGDisplayBounds(displayID)
                let relX = cocoa.x - screen.frame.minX
                let relYFromBottom = cocoa.y - screen.frame.minY
                // Quartz Y grows down from top of this display's bounds.
                let qy = bounds.minY + (screen.frame.height - relYFromBottom)
                let qx = bounds.minX + relX
                return CGPoint(x: qx, y: qy)
            }
        }
        // Fallback: primary height flip (single-display-ish).
        let h = CGDisplayBounds(CGMainDisplayID()).height
        return CGPoint(x: cocoa.x, y: h - cocoa.y)
    }

    /// Ensure a Quartz point lies on some display (center of main if not).
    func clampQuartzToVisible(_ point: CGPoint) -> CGPoint {
        if displayContaining(quartzPoint: point) != nil {
            return point
        }
        if let main = displays.first(where: \.isMain) ?? displays.first {
            return CGPoint(x: main.quartzFrame.midX, y: main.quartzFrame.midY)
        }
        return point
    }
}
