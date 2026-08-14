import Foundation
import CoreGraphics
import Cocoa

/// Stable identity for a display across reboots / login (CGDirectDisplayID is *not* stable).
struct DisplayFingerprint: Codable, Equatable {
    var displayID: UInt32
    var uuid: String
    var name: String
    var isBuiltin: Bool
    var width: Int
    var height: Int

    var isPortrait: Bool { height > width }

    static func from(display: DisplayInfo) -> DisplayFingerprint {
        DisplayFingerprint(
            displayID: display.id,
            uuid: DisplayIdentity.uuidString(for: display.id) ?? "",
            name: display.name,
            isBuiltin: display.isBuiltin,
            width: Int(display.cocoaFrame.width.rounded()),
            height: Int(display.cocoaFrame.height.rounded())
        )
    }
}

enum DisplayIdentity {
    /// Hardware UUID for a display when available (stable across sessions).
    static func uuidString(for displayID: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(displayID)?.takeRetainedValue() else {
            return nil
        }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// Resolve a previously saved fingerprint to a *live* display ID.
    /// Returns nil only if no reasonable match exists.
    static func resolve(_ fp: DisplayFingerprint?, among displays: [DisplayInfo]) -> CGDirectDisplayID? {
        guard let fp, !displays.isEmpty else { return nil }

        // 1) Exact live display ID (same session)
        if fp.displayID != 0, displays.contains(where: { $0.id == fp.displayID }) {
            return fp.displayID
        }

        // 2) Hardware UUID
        if !fp.uuid.isEmpty {
            for d in displays {
                if uuidString(for: d.id) == fp.uuid {
                    return d.id
                }
            }
        }

        // 3) Name + built-in flag (unique)
        let nameBuiltin = displays.filter { $0.name == fp.name && $0.isBuiltin == fp.isBuiltin }
        if nameBuiltin.count == 1 { return nameBuiltin[0].id }

        // 4) Unique name
        let byName = displays.filter { $0.name == fp.name }
        if byName.count == 1 { return byName[0].id }

        // 5) Same orientation class + same built-in flag (e.g. portrait external)
        let portrait = fp.isPortrait
        let orientMatch = displays.filter {
            $0.isBuiltin == fp.isBuiltin
                && (($0.cocoaFrame.height > $0.cocoaFrame.width) == portrait)
        }
        if orientMatch.count == 1 { return orientMatch[0].id }

        // 6) Prefer non-built-in if saved default was external
        if !fp.isBuiltin {
            let externals = displays.filter { !$0.isBuiltin }
            if externals.count == 1 { return externals[0].id }
            // Unique external matching name prefix / contains
            let loose = externals.filter {
                $0.name.localizedCaseInsensitiveContains(fp.name)
                    || fp.name.localizedCaseInsensitiveContains($0.name)
            }
            if loose.count == 1 { return loose[0].id }
        }

        return nil
    }
}
