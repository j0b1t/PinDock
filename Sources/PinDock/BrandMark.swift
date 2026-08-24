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

/// Same raised fill as the selected sidebar item.
struct PinDockGlassChip: View {
    @Environment(\.colorScheme) private var colorScheme
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.primary.opacity(colorScheme == .dark ? 0.12 : 0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
            .shadow(color: Color.black.opacity(colorScheme == .dark ? 0.28 : 0.08), radius: 5, y: 1)
    }
}

/// Menu-bar / window status chip: green/grey dot + On/Off.
struct PinDockStatusChip: View {
    @ObservedObject var state: AppState
    var elevated: Bool = false

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(state.isEnabled && state.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 9, height: 9)
            Text(state.isEnabled ? L10n.t("on") : L10n.t("off"))
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background { if elevated { PinDockGlassChip() } }
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

/// Desktop shows through — Apple-style translucent gray, not a flat fill.
struct GlassBackdrop: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var emphasized: Bool = true

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = emphasized
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
        view.isEmphasized = emphasized
        view.state = .active
        view.blendingMode = .behindWindow
    }
}

/// Fixed RGB so pills and switches stay blue/orange when the window is not key.
/// `Color.accentColor` turns gray in an inactive menu-bar popover.
enum PinDockColor {
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let dock = Color(red: 1.0, green: 0.584, blue: 0.0)
}

/// Shared liquid-glass fill. Dark = charcoal HUD. Light = the same HUD without darkening.
struct PinDockGlass: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Popover chrome already blurs; only draw the wash so we don’t stack two materials.
    var fillMaterial: Bool = true
    var applyWash: Bool = true

    var body: some View {
        ZStack {
            if fillMaterial {
                GlassBackdrop(material: .hudWindow, emphasized: false)
            }
            if applyWash {
                if colorScheme == .dark {
                    Rectangle()
                        .fill(Color.black.opacity(0.10))
                        .blendMode(.plusDarker)
                    Rectangle()
                        .fill(Color.white.opacity(0.08))
                        .blendMode(.plusLighter)
                } else {
                    Rectangle()
                        .fill(Color.black.opacity(0.10))
                        .blendMode(.plusDarker)
                }
            }
        }
    }
}

/// Frosted cards on top of PinDockGlass.
struct PinDockCardFill: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Rectangle()
            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
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
