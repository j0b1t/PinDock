import SwiftUI
import AppKit

/// Pin glyph without the blue app-icon chrome (template, follows light/dark).
struct PinDockMark: View {
    var size: CGFloat = 22

    var body: some View {
        Group {
            if let image = Self.image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .renderingMode(.template)
                    .aspectRatio(contentMode: .fit)
            } else {
                Image(systemName: "pin.fill")
                    .font(.system(size: size * 0.72, weight: .semibold))
            }
        }
        .foregroundStyle(.primary)
        .frame(width: size, height: size)
        .accessibilityLabel("PinDock")
    }

    private static let image: NSImage? = {
        if let named = NSImage(named: "HeaderLogo") {
            named.isTemplate = true
            return named
        }
        if let url = Bundle.main.url(forResource: "HeaderLogo", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = true
            return img
        }
        return nil
    }()
}

/// Menu-bar / window status chip: green/grey dot + On/Off.
struct PinDockStatusChip: View {
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isEnabled && state.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
            Text(state.isEnabled ? L10n.t("on") : L10n.t("off"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .help(state.statusLine)
    }
}

/// Full-color app icon for the window title bar.
struct PinDockAppIcon: View {
    var size: CGFloat = 24

    var body: some View {
        Image(nsImage: NSApp.applicationIconImage ?? NSImage(size: NSSize(width: size, height: size)))
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
            .accessibilityLabel("PinDock")
    }
}

/// macOS 26 Liquid Glass. Regular is the thick plate; clear is the lighter group on top of it.
struct LiquidGlassBackdrop: NSViewRepresentable {
    var clear: Bool = false
    var cornerRadius: CGFloat = 0

    func makeNSView(context: Context) -> NSView {
        guard #available(macOS 26.0, *) else { return NSView() }
        let glass = NSGlassEffectView()
        glass.style = clear ? .clear : .regular
        glass.cornerRadius = cornerRadius
        return glass
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard #available(macOS 26.0, *), let glass = view as? NSGlassEffectView else { return }
        glass.style = clear ? .clear : .regular
        glass.cornerRadius = cornerRadius
    }
}

/// Desktop shows through. Dark uses the HUD. Light forces Aqua so the frost stays pale.
struct GlassBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var emphasized: Bool = true
    var appearance: NSAppearance.Name? = nil

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        configure(view)
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        configure(view)
    }

    private func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = emphasized
        view.appearance = appearance.flatMap { NSAppearance(named: $0) }
    }
}

/// Fixed RGB so pills and switches stay blue/orange when the window is not key.
/// `Color.accentColor` turns gray in an inactive menu-bar popover.
enum PinDockColor {
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let dock = Color(red: 1.0, green: 0.584, blue: 0.0)
}

/// Critically damped motion. No bounce. Reduced motion snaps instead of sliding.
enum PinDockMotion {
    static let settle = Animation.spring(response: 0.35, dampingFraction: 1)

    static func settle(reduceMotion: Bool) -> Animation? {
        reduceMotion ? nil : settle
    }
}

/// Where a glass surface sits. The plate is the thick window. A group is the lighter card on top of it.
enum PinDockGlassRole {
    case plate
    case group
}

/// Shared glass fill. On macOS 26 this is the system Liquid Glass and follows Light or Dark.
/// Older systems keep the HUD / pale-popover fallback.
struct PinDockGlass: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast
    var role: PinDockGlassRole = .plate
    /// Popover chrome already blurs; only draw the wash so we don’t stack two materials.
    var fillMaterial: Bool = true
    var applyWash: Bool = true

    var body: some View {
        ZStack {
            if reduceTransparency {
                Rectangle()
                    .fill(colorScheme == .dark ? Color(white: 0.16) : Color(white: 0.96))
            } else if fillMaterial {
                if #available(macOS 26.0, *) {
                    LiquidGlassBackdrop(clear: role == .group, cornerRadius: role == .group ? 12 : 0)
                } else if colorScheme == .dark {
                    GlassBackdrop(material: .hudWindow, emphasized: false)
                } else {
                    GlassBackdrop(material: .popover, emphasized: true, appearance: .aqua)
                }
            }
            if applyWash, !reduceTransparency, #unavailable(macOS 26.0) {
                if colorScheme == .dark {
                    Rectangle()
                        .fill(Color.black.opacity(0.10))
                        .blendMode(.plusDarker)
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .blendMode(.plusLighter)
                } else {
                    Rectangle()
                        .fill(Color.white.opacity(0.10))
                }
            }
            if contrast == .increased {
                Rectangle()
                    .stroke(Color.primary.opacity(0.55), lineWidth: 1)
            }
        }
    }
}

/// Frosted cards on top of PinDockGlass.
struct PinDockCardFill: View {
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        ZStack(alignment: .top) {
            Rectangle().fill(cardColor)
            if !reduceTransparency, #available(macOS 26.0, *) {
                // Light catches the top edge of a glass group.
                Rectangle()
                    .fill(Color.white.opacity(colorScheme == .dark ? 0.16 : 0.65))
                    .frame(height: 0.6)
            }
        }
        .overlay {
            if contrast == .increased {
                Rectangle().stroke(Color.primary.opacity(0.55), lineWidth: 1)
            }
        }
    }

    private var cardColor: Color {
        if reduceTransparency {
            return colorScheme == .dark ? Color(white: 0.24) : Color(white: 0.98)
        }
        if #available(macOS 26.0, *) {
            return colorScheme == .dark ? Color.white.opacity(0.08) : Color.white.opacity(0.22)
        }
        return colorScheme == .dark ? Color.white.opacity(0.10) : Color.white.opacity(0.38)
    }
}

/// Triangle that fills the NSPopover arrow using the same PinDockGlass as the panel.
struct PinDockPopoverArrow: View {
    var body: some View {
        PinDockGlass()
            .mask(PopoverArrowShape())
    }
}

private struct PopoverArrowShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: 0, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
