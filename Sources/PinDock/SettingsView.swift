import SwiftUI
import AppKit

/// Control-Center-style panel shown in an `NSPopover` or a standalone window.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    /// Compact = menu-bar popover; false = larger standalone window.
    var compact: Bool = true

    private var panelWidth: CGFloat { compact ? 360 : 420 }
    /// Tall enough that Displays → Allowed → Behavior fit without scrolling
    /// when no banners are showing (Permissions / Updates may still scroll).
    private var panelMaxHeight: CGFloat { compact ? 680 : 820 }

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                MainWindowView(state: state)
            }
        }
        .onAppear {
            state.refresh()
            if state.autoCheckForUpdates {
                state.checkForUpdates(force: false)
            }
        }
    }

    private var compactBody: some View {
        VStack(spacing: 0) {
            header
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 14) {
                    if state.updateAvailable { updateBanner }
                    if state.dockIsAway { moveBackBanner }
                    if showsAccessibilityBanner {
                        accessibilityBanner
                    }
                    defaultSection
                    allowListSection
                    appearanceSection
                    behaviorSection
                    permissionsSection
                    updatesSection
                    footer
                }
                .padding(14)
            }
        }
        .frame(width: panelWidth)
        .frame(maxHeight: panelMaxHeight)
        .background { glassBackground }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Maintainer: `PinDock --ui-preview-a11y` forces the Accessibility banner for screenshots.
    private var showsAccessibilityBanner: Bool {
        if CommandLine.arguments.contains("--ui-preview-a11y") { return true }
        return !state.isTrusted || (state.isEnabled && !state.isRunning)
    }

    // MARK: - Glass

    @ViewBuilder
    private var glassBackground: some View {
        // System materials approximate Control Center / Liquid Glass on older OS;
        // on macOS 26+ popover chrome also adopts glass more automatically.
        ZStack {
            Rectangle().fill(.ultraThinMaterial)
            Rectangle()
                .fill(
                    colorScheme == .dark
                        ? Color.white.opacity(0.04)
                        : Color.white.opacity(0.35)
                )
                .blendMode(.plusLighter)
        }
    }

    // MARK: - Header

    /// App pin logo without the blue icon background (template → follows light/dark).
    @ViewBuilder
    private var headerAppLogo: some View {
        if let image = Self.headerLogoImage {
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .renderingMode(.template)
                .aspectRatio(contentMode: .fit)
                .foregroundStyle(.primary)
                .accessibilityLabel("PinDock")
        } else {
            Image(systemName: "pin.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.primary)
                .accessibilityLabel("PinDock")
        }
    }

    private static let headerLogoImage: NSImage? = {
        // Prefer Resources/HeaderLogo.png (+ @2x) from the app bundle.
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

    private var header: some View {
        HStack(spacing: 10) {
            headerAppLogo
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("PinDock")
                    .font(.system(size: 14, weight: .semibold))
                Text(state.statusLine)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Toggle("", isOn: $state.isEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
                .help(state.isEnabled ? "Pinning on" : "Pinning off")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.55))
    }

    // MARK: - Banners

    private var updateBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Update available")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Version \(state.latestRemoteVersion ?? "") on GitHub")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                if state.isInstallingUpdate {
                    ProgressView(value: state.updateProgress)
                        .frame(width: 72)
                    Text("\(Int(state.updateProgress * 100))%")
                        .font(.system(size: 10).monospacedDigit())
                        .foregroundStyle(.secondary)
                } else {
                    HStack(spacing: 6) {
                        if state.updateDownloadURL != nil {
                            Button("Install") { state.installAvailableUpdate() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .font(.system(size: 12, weight: .medium))
                        }
                        Button("View") { state.openReleasePage() }
                            .controlSize(.regular)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            if !state.updateErrorMessage.isEmpty {
                Text(state.updateErrorMessage)
                    .font(.system(size: 10))
                    .foregroundStyle(.red)
            }
        }
        .padding(10)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var moveBackBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.uturn.backward.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Color.accentColor)
            VStack(alignment: .leading, spacing: 2) {
                Text("Dock away from default")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(DisplayManager.shared.name(for: state.actualDockDisplayID != 0 ? state.actualDockDisplayID : state.currentDockDisplayID)) → \(DisplayManager.shared.name(for: state.defaultDisplayID))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button("Move Back") { state.moveBackToDefault() }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
                .frame(minHeight: 32)
                .keyboardShortcut("d", modifiers: [.command, .shift])
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(Color.accentColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var accessibilityBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 18))
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Accessibility needed")
                    .font(.system(size: 12, weight: .semibold))
                Text("PinDock needs Accessibility to lock the Dock. Grant access, then Retry.")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button("Grant…") { state.openAccessibility() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .font(.system(size: 12, weight: .medium))
                Button("Retry") { state.retryEngine() }
                    .controlSize(.regular)
                    .font(.system(size: 12, weight: .medium))
            }
        }
        .padding(10)
        .background(Color.orange.opacity(0.14))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .strokeBorder(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }

    private func compactBanner<Trailing: View>(
        icon: String,
        title: String,
        detail: String,
        iconColor: Color = Color.accentColor,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(iconColor)
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
                Text(detail)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 4)
            trailing()
        }
        .padding(10)
        .background(iconColor.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - Arrangement

    private var defaultSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Displays")
            Text("Tap a display to move the Dock. Default is unchanged.")
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            DisplayMapView(
                displays: state.displays,
                defaultID: state.defaultDisplayID,
                actualDockID: state.actualDockDisplayID,
                acquiringID: 0,
                blockedIDs: state.blockedDisplayIDs
            ) { id in
                state.moveDockToDisplay(id)
            }
            .frame(height: 110)
            .padding(8)
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Allow list

    private var allowListSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Allowed for Dock")
            VStack(spacing: 0) {
                ForEach(Array(state.displays.enumerated()), id: \.element.id) { index, display in
                    DisplayAllowRow(
                        display: display,
                        isDefault: display.id == state.defaultDisplayID,
                        isActualDock: state.isActualDockHost(display.id),
                        isAllowed: state.isAllowed(display.id),
                        onToggleAllowed: { allowed in
                            state.setAllowed(display.id, allowed: allowed)
                        },
                        onSetDefault: {
                            state.setDefaultOnly(to: display.id)
                        }
                    )
                    if index < state.displays.count - 1 {
                        Divider().padding(.leading, 12)
                    }
                }
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Appearance

    private var appearanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Appearance")
            VStack(spacing: 0) {
                settingsRow("Show PinDock", state.appPresentation.subtitle) {
                    Picker("", selection: $state.appPresentation) {
                        ForEach(AppPresentation.allCases) { mode in
                            Text(mode.shortLabel).tag(mode)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 118)
                }
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Behavior / shortcuts

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Behavior")
            VStack(spacing: 0) {
                settingsRow("Move Back", "⌘⇧D") {
                    Text("⌘⇧D")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Divider().padding(.leading, 12)
                settingsRow("Modifier", "Hold at bottom edge") {
                    Picker("", selection: $state.modifierKey) {
                        ForEach(ModifierKey.allCases) { key in
                            Text(key.shortLabel).tag(key)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 100)
                }
                Divider().padding(.leading, 12)
                settingsRow("Restore on wake", "And when monitors change") {
                    Toggle("", isOn: $state.restoreOnWake)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
                Divider().padding(.leading, 12)
                settingsRow("Launch at login", "Start when you sign in") {
                    Toggle("", isOn: $state.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Permissions")
            VStack(spacing: 0) {
                settingsRow(
                    "Accessibility",
                    state.isTrusted ? "Granted — required for locking" : "Required for locking"
                ) {
                    if state.isTrusted {
                        Label("Active", systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        HStack(spacing: 6) {
                            Button("Grant…") { state.openAccessibility() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                                .font(.system(size: 12, weight: .medium))
                            Button("Retry") { state.retryEngine() }
                                .controlSize(.regular)
                                .font(.system(size: 12, weight: .medium))
                        }
                    }
                }
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Updates

    private var updatesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel("Updates")
            VStack(spacing: 0) {
                settingsRow("Auto check", "Off by default · launch & every 12h when on") {
                    Toggle("", isOn: $state.autoCheckForUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                }
                Divider().padding(.leading, 12)
                settingsRow(
                    "Auto install",
                    state.autoCheckForUpdates
                        ? "Verified GitHub ZIP only (SHA + codesign)"
                        : "Enable auto check first"
                ) {
                    Toggle("", isOn: $state.autoInstallUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .disabled(!state.autoCheckForUpdates)
                }
                Divider().padding(.leading, 12)
                settingsRow("Status", updateSubtitle) {
                    if state.isCheckingUpdate || state.isInstallingUpdate {
                        ProgressView().controlSize(.regular)
                    } else if state.updateAvailable {
                        HStack(spacing: 6) {
                            if state.updateDownloadURL != nil {
                                Button("Install") { state.installAvailableUpdate() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.regular)
                                    .font(.system(size: 12, weight: .medium))
                            }
                            Button("View") { state.openReleasePage() }
                                .controlSize(.regular)
                                .font(.system(size: 12, weight: .medium))
                        }
                    } else {
                        Button("Check") { state.checkForUpdates(force: true) }
                            .controlSize(.regular)
                            .font(.system(size: 12, weight: .medium))
                    }
                }
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var updateSubtitle: String {
        if state.isInstallingUpdate {
            return "Installing…"
        }
        if state.updateAvailable, let v = state.latestRemoteVersion {
            return state.autoInstallUpdates ? "\(v) — auto install" : "\(v) available"
        }
        if !state.updateCheckIdleMessage.isEmpty {
            return state.updateCheckIdleMessage
        }
        return "GitHub Releases"
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Version \(state.appVersion)")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)

            VStack(alignment: .leading, spacing: 5) {
                Text("Support PinDock")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text("Optional tip — never required.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                HStack(spacing: 8) {
                    supportChip("Lightning", systemImage: "bolt.fill",
                                url: URL(string: "https://strike.me/j0b1t")!)
                    supportChip("Ko‑fi", systemImage: "cup.and.saucer.fill",
                                url: URL(string: "https://ko-fi.com/j0b1t")!)
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func supportChip(_ title: String, systemImage: String, url: URL) -> some View {
        Link(destination: url) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9, weight: .semibold))
                Text(title)
                    .font(.system(size: 10, weight: .medium))
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 5)
            .background(.ultraThinMaterial)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary.opacity(0.9))
    }

    // MARK: - Helpers

    private func settingsRow<Trailing: View>(
        _ title: String,
        _ subtitle: String,
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .tracking(0.3)
    }

    private var chipFill: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(.thinMaterial)
    }
}

// MARK: - Rows

struct DisplayAllowRow: View {
    let display: DisplayInfo
    let isDefault: Bool
    let isActualDock: Bool
    let isAllowed: Bool
    let onToggleAllowed: (Bool) -> Void
    let onSetDefault: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: Binding(
                get: { isAllowed },
                set: { onToggleAllowed($0) }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.mini)
            .help(isAllowed ? "Allowed" : "Blocked")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(display.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if isDefault { pill("Default", Color.accentColor) }
                    if isActualDock { pill("Dock", Color.orange) }
                    if !isAllowed { pill("Off", Color.secondary) }
                }
                Text(display.isMain ? "Main · \(sizeLabel)" : sizeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(isDefault ? "Default" : "Set default") {
                onSetDefault()
            }
            .buttonStyle(.bordered)
            .controlSize(.regular)
            .font(.system(size: 12, weight: .medium))
            .disabled(!isAllowed || isDefault)
            .help("Status only — does not move the Dock")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .opacity(isAllowed ? 1 : 0.6)
    }

    private func pill(_ text: String, _ color: Color) -> some View {
        Text(text)
            .font(.system(size: 8, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(color.opacity(0.9))
            .clipShape(Capsule())
    }

    private var sizeLabel: String {
        "\(Int(display.cocoaFrame.width))×\(Int(display.cocoaFrame.height))"
    }
}

// MARK: - Map

struct DisplayMapView: View {
    let displays: [DisplayInfo]
    let defaultID: UInt32
    let actualDockID: UInt32
    let acquiringID: UInt32
    let blockedIDs: Set<UInt32>
    let onSelect: (UInt32) -> Void

    var body: some View {
        GeometryReader { geo in
            let layout = Self.layout(displays: displays, in: geo.size)
            ZStack {
                ForEach(layout, id: \.id) { item in
                    let isDefault = item.id == defaultID
                    let isCurrent = actualDockID != 0 && item.id == actualDockID
                    let blocked = blockedIDs.contains(item.id)
                    Button {
                        if !blocked { onSelect(item.id) }
                    } label: {
                        ZStack {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    blocked ? Color.primary.opacity(0.05)
                                    : isCurrent ? Color.orange.opacity(0.85)
                                    : isDefault ? Color.accentColor.opacity(0.30)
                                    : Color.primary.opacity(0.07)
                                )
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    blocked ? Color.secondary.opacity(0.3)
                                    : isCurrent ? Color.orange
                                    : isDefault ? Color.accentColor
                                    : Color.primary.opacity(0.1),
                                    style: StrokeStyle(
                                        lineWidth: (isDefault || isCurrent) ? 1.5 : 1,
                                        dash: blocked ? [3, 2] : []
                                    )
                                )
                            VStack(spacing: 2) {
                                if blocked {
                                    Image(systemName: "nosign")
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.secondary)
                                }
                                Text(item.shortName)
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundStyle(isCurrent && !blocked ? .white : .primary)
                                    .lineLimit(2)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 4)
                                if isCurrent {
                                    Text("Dock")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                } else if isDefault {
                                    Text("Default")
                                        .font(.system(size: 8, weight: .semibold))
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                        }
                        .frame(width: item.rect.width, height: item.rect.height)
                    }
                    .buttonStyle(.plain)
                    .disabled(blocked)
                    .position(x: item.rect.midX, y: item.rect.midY)
                }
            }
        }
    }

    private struct LayoutItem: Identifiable {
        let id: UInt32
        let shortName: String
        let isMain: Bool
        let rect: CGRect
    }

    private static func layout(displays: [DisplayInfo], in size: CGSize) -> [LayoutItem] {
        guard !displays.isEmpty else { return [] }
        let frames = displays.map(\.cocoaFrame)
        let minX = frames.map(\.minX).min() ?? 0
        let maxX = frames.map(\.maxX).max() ?? 1
        let minY = frames.map(\.minY).min() ?? 0
        let maxY = frames.map(\.maxY).max() ?? 1
        let worldW = max(maxX - minX, 1)
        let worldH = max(maxY - minY, 1)
        let scale = min((size.width - 10) / worldW, (size.height - 10) / worldH) * 0.9
        let contentW = worldW * scale
        let contentH = worldH * scale
        let ox = (size.width - contentW) / 2
        let oy = (size.height - contentH) / 2
        return displays.map { d in
            let f = d.cocoaFrame
            let w = max(f.width * scale, 56)
            let h = max(f.height * scale, 36)
            let x = ox + (f.minX - minX) * scale
            let yFromBottom = (f.minY - minY) * scale
            let y = oy + (contentH - yFromBottom - h)
            let short = d.name.count > 14 ? String(d.name.prefix(12)) + "…" : d.name
            return LayoutItem(id: d.id, shortName: short, isMain: d.isMain,
                              rect: CGRect(x: x, y: y, width: w, height: h))
        }
    }
}
