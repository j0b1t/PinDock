import AppKit
import SwiftUI

/// Light-mode control fill: a faint veil so the card shows through.
struct PinDockLightControlChrome: View {
    var cornerRadius: CGFloat = 8

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(Color.primary.opacity(0.07))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.10), lineWidth: 0.5)
            }
    }
}

/// Menu picker. Both appearances use the same large popup, so the field and arrow match in size.
struct PinDockMenuPicker<Selection: Hashable>: View {
    @Binding var selection: Selection
    var options: [Selection]
    var title: (Selection) -> String

    var body: some View {
        PopupButton(selection: $selection, options: options, title: title)
            .fixedSize()
    }
}

/// Native large popup. Appearance follows light or dark; the control size does not.
private struct PopupButton<Selection: Hashable>: NSViewRepresentable {
    @Binding var selection: Selection
    var options: [Selection]
    var title: (Selection) -> String

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSPopUpButton {
        let button = NSPopUpButton(frame: .zero, pullsDown: false)
        button.controlSize = .large
        button.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        button.target = context.coordinator
        button.action = #selector(Coordinator.pick(_:))
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        button.setContentHuggingPriority(.required, for: .horizontal)
        button.isBordered = true
        return button
    }

    func updateNSView(_ button: NSPopUpButton, context: Context) {
        context.coordinator.parent = self
        if !button.isBordered {
            button.isBordered = true
        }
        let titles = options.map { title($0) }
        if button.itemTitles != titles {
            button.removeAllItems()
            for name in titles {
                button.addItem(withTitle: name)
            }
        }
        if let index = options.firstIndex(of: selection), button.indexOfSelectedItem != index {
            button.selectItem(at: index)
        }
    }

    final class Coordinator: NSObject {
        var parent: PopupButton
        init(_ parent: PopupButton) { self.parent = parent }

        @objc func pick(_ sender: NSPopUpButton) {
            let index = sender.indexOfSelectedItem
            guard parent.options.indices.contains(index) else { return }
            let next = parent.options[index]
            if parent.selection != next {
                parent.selection = next
            }
        }
    }
}

/// Dock / Settings switch. Dark keeps the system segments. Light uses a clear track instead of a solid white pill.
struct PinDockLightSegments<Selection: Hashable>: View {
    @Binding var selection: Selection
    var options: [(Selection, String)]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(Array(options.enumerated()), id: \.offset) { _, option in
                let on = option.0 == selection
                Button {
                    selection = option.0
                } label: {
                    Text(option.1)
                        .font(.system(size: 13, weight: on ? .semibold : .medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                        .background {
                            if on {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(Color.white.opacity(0.38))
                                    .overlay {
                                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                                            .strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5)
                                    }
                            }
                        }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(3)
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(0.06))
        }
    }
}

extension View {
    /// Secondary button. Light mode is a clear field; dark mode stays the system bordered button.
    func pindockBorderedButton() -> some View {
        modifier(PinDockBorderedButtonModifier())
    }
}

private struct PinDockBorderedButtonModifier: ViewModifier {
    @Environment(\.colorScheme) private var colorScheme

    @ViewBuilder
    func body(content: Content) -> some View {
        if colorScheme == .light {
            content.buttonStyle(PinDockLightGlassButtonStyle())
        } else {
            content.buttonStyle(PinDockDarkGlassButtonStyle())
        }
    }
}

private struct PinDockLightGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background { PinDockLightControlChrome() }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
    }
}

/// Same metrics as the light button. Only the fill stays dark.
private struct PinDockDarkGlassButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.14))
                    .overlay {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.16), lineWidth: 0.5)
                    }
            }
            .opacity(isEnabled ? (configuration.isPressed ? 0.72 : 1) : 0.42)
    }
}
