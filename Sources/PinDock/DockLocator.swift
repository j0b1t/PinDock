import Cocoa
import CoreGraphics

/// Detects which display currently hosts the macOS Dock by comparing
/// each screen's full frame vs visibleFrame (dock reserves space).
enum DockLocator {

    /// Bottom/side inset that indicates the Dock (not just the menu bar).
    private static let dockInsetThreshold: CGFloat = 20

    /// Returns the display ID that currently has the Dock, if detectable.
    static func displayIDHostingDock() -> CGDirectDisplayID? {
        DisplayManager.shared.refreshIfNeeded()

        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            let id = CGDirectDisplayID(number.uint32Value)
            if screenHostsDock(screen) {
                return id
            }
        }
        return nil
    }

    /// True when `visibleFrame` is smaller than `frame` in a way that indicates Dock chrome
    /// (bottom, left, or right). Menu-bar-only inset at the top does not count.
    static func screenHostsDock(_ screen: NSScreen) -> Bool {
        let full = screen.frame
        let visible = screen.visibleFrame

        // Cocoa: origin bottom-left. Dock at bottom raises visible.minY.
        let bottomInset = visible.minY - full.minY
        if bottomInset >= dockInsetThreshold {
            return true
        }

        // Dock on left: visible.minX > full.minX
        let leftInset = visible.minX - full.minX
        if leftInset >= dockInsetThreshold {
            return true
        }

        // Dock on right: full.maxX - visible.maxX
        let rightInset = full.maxX - visible.maxX
        if rightInset >= dockInsetThreshold {
            return true
        }

        return false
    }

    /// How many points of bottom inset the Dock (or anything) reserves on this display.
    static func bottomReservedHeight(on displayID: CGDirectDisplayID) -> CGFloat {
        for screen in NSScreen.screens {
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                continue
            }
            if CGDirectDisplayID(number.uint32Value) == displayID {
                return max(0, screen.visibleFrame.minY - screen.frame.minY)
            }
        }
        return 0
    }
}
