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

/// Full-color app icon (blue PinDock symbol).
struct PinDockAppIcon: View {
    var size: CGFloat = 28

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

/// Behind-window glass so desktop shows through (Liquid Glass / vibrancy).
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
        view.blendingMode = .behindWindow
    }
}
