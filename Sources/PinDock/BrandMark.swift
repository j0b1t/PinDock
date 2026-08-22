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
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
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

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .followsWindowActiveState
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

/// Fixed RGB so pills and switches stay blue/orange when the window is not key.
/// `Color.accentColor` turns gray in an inactive menu-bar popover.
enum PinDockColor {
    static let accent = Color(red: 0.0, green: 0.478, blue: 1.0)
    static let dock = Color(red: 1.0, green: 0.584, blue: 0.0)
}

/// Shared liquid-glass fill for window, title bar, and menu-bar panel.
struct PinDockGlass: View {
    @Environment(\.colorScheme) private var colorScheme
    /// Menu-bar popover already has a visual-effect bubble; only add the highlight.
    var fillMaterial: Bool = true

    var body: some View {
        ZStack {
            if fillMaterial {
                Rectangle().fill(.ultraThinMaterial)
            }
            Rectangle()
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.08)
                        : Color.white.opacity(0.32)
                )
                .blendMode(.plusLighter)
        }
    }
}
