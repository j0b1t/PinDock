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
        HStack(spacing: 6) {
            Circle()
                .fill(state.isEnabled && state.isRunning ? Color.green : Color.secondary.opacity(0.4))
                .frame(width: 7, height: 7)
            Text(state.isEnabled ? L10n.t("on") : L10n.t("off"))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
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
