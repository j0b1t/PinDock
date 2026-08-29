import SwiftUI
import AppKit

/// Control-Center-style panel shown in an `NSPopover` or a standalone window.
struct SettingsView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    /// Compact = menu-bar popover; false = larger standalone window.
    var compact: Bool = true

    private enum CompactTab: Hashable {
        case dock
        case settings
    }

    @State private var compactTab: CompactTab =
        CommandLine.arguments.contains("--ui-preview-settings") ? .settings : .dock

    /// Wide enough that “Show PinDock” + “Menu bar and App” stay on one row.
    static let compactPanelSize = CGSize(width: 440, height: 540)

    private var panelWidth: CGFloat { compact ? Self.compactPanelSize.width : 420 }

    var body: some View {
        Group {
            if compact {
                compactBody
            } else {
                MainWindowView(state: state)
            }
        }
        .id(state.appLanguage)
        .onChange(of: state.menuBarOpenNonce) { _ in
            compactTab = .dock
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
            Picker("", selection: $compactTab) {
                Text(L10n.t("tab.dock")).tag(CompactTab.dock)
                Text(L10n.t("tab.settings")).tag(CompactTab.settings)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 14)
            .padding(.top, 4)
            .padding(.bottom, 10)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    if compactTab == .dock {
                        if state.updateAvailable { updateBanner }
                        if state.dockIsAway { moveBackBanner }
                        if showsAccessibilityBanner { accessibilityBanner }
                        pinDockEnableSection
                        defaultSection
                        allowListSection
                    } else {
                        appearanceSection
                        behaviorSection
                        permissionsSection
                        updatesSection
                        footer
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
            }
        }
        // Fixed size so the popover does not jump when switching Dock / Settings.
        .frame(width: panelWidth, height: Self.compactPanelSize.height)
        .background { glassBackground }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .foregroundStyle(.primary)
        // Menu-bar panel is often not the key window — keep glass/controls looking active.
        .environment(\.controlActiveState, .key)
    }

    /// Maintainer: `PinDock --ui-preview-a11y` forces the Accessibility banner for screenshots.
    private var showsAccessibilityBanner: Bool {
        if CommandLine.arguments.contains("--ui-preview-a11y") { return true }
        return !state.isTrusted || (state.isEnabled && !state.isRunning)
    }

    // MARK: - Glass

    @ViewBuilder
    private var glassBackground: some View {
        PinDockGlass()
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            PinDockMark(size: 26)
            Text("PinDock")
                .font(.system(size: 14, weight: .semibold))
            Spacer(minLength: 8)
            PinDockStatusChip(state: state)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    // MARK: - Banners

    private var updateBanner: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 16))
                    .foregroundStyle(PinDockColor.accent)
                VStack(alignment: .leading, spacing: 1) {
                    Text(L10n.t("update.banner"))
                        .font(.system(size: 12, weight: .semibold))
                    Text(L10n.t("update.banner.body", state.latestRemoteVersion ?? ""))
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
                            Button(L10n.t("install")) { state.installAvailableUpdate() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                        }
                        Button(L10n.t("view")) { state.openReleasePage() }
                            .controlSize(.regular)
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
                .foregroundStyle(PinDockColor.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(L10n.t("dockAway"))
                    .font(.system(size: 12, weight: .semibold))
                Text("\(DisplayManager.shared.name(for: state.actualDockDisplayID != 0 ? state.actualDockDisplayID : state.currentDockDisplayID)) → \(DisplayManager.shared.name(for: state.defaultDisplayID))")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer(minLength: 6)
            Button(L10n.t("moveBack")) { state.moveBackToDefault() }
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
                Text(L10n.t("accessibility.needed"))
                    .font(.system(size: 12, weight: .semibold))
                Text(L10n.t("accessibility.body"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 4)
            VStack(spacing: 6) {
                Button(L10n.t("grant")) { state.openAccessibility() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                Button(L10n.t("retry")) { state.retryEngine() }
                    .controlSize(.regular)
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
        iconColor: Color = PinDockColor.accent,
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

    // MARK: - Enable PinDock

    private var pinDockEnableSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                PinDockMark(size: 14)
                Text("PinDock")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
            }
            settingsRow(L10n.t("enable"), L10n.t("enable.hint")) {
                Toggle("", isOn: $state.isEnabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .tint(PinDockColor.accent)
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Arrangement

    private var defaultSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(L10n.t("pane.displays"), systemImage: "display.2")
            Text(L10n.t("tapDisplay"))
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
            sectionLabel(L10n.t("allowed"), systemImage: "checkmark.circle")
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
            sectionLabel(L10n.t("pane.appearance"), systemImage: "macwindow")
            VStack(spacing: 0) {
                settingsRow(L10n.t("showPinDock"), state.appPresentation.localizedSubtitle) {
                    Picker("", selection: $state.appPresentation) {
                        ForEach(AppPresentation.allCases) { mode in
                            Text(mode.localizedLabel).tag(mode)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider().padding(.leading, 12)
                settingsRow(L10n.t("theme"), L10n.t("theme.hint")) {
                    Picker("", selection: $state.appColorScheme) {
                        ForEach(AppColorScheme.allCases) { scheme in
                            Text(scheme.localizedLabel).tag(scheme)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider().padding(.leading, 12)
                settingsRow(L10n.t("language"), L10n.t("language.hint")) {
                    Picker("", selection: $state.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Behavior / shortcuts

    private var behaviorSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(L10n.t("pane.behavior"), systemImage: "slider.horizontal.3")
            VStack(spacing: 0) {
                settingsRow(L10n.t("autohide"), L10n.t("autohide.hint")) {
                    Toggle("", isOn: $state.dockAutoHide)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .tint(PinDockColor.accent)
                }
                Divider().padding(.leading, 12)
                settingsRow(L10n.t("moveBack"), "⌘⇧D") {
                    Text("⌘⇧D")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                Divider().padding(.leading, 12)
                settingsRow(L10n.t("modifier"), L10n.t("modifier.hint")) {
                    Picker("", selection: $state.modifierKey) {
                        ForEach(ModifierKey.allCases) { key in
                            Text(key.localizedLabel).tag(key)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                Divider().padding(.leading, 12)
                settingsRow(L10n.t("restoreWake"), L10n.t("restoreWake.hint")) {
                    Toggle("", isOn: $state.restoreOnWake)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .tint(PinDockColor.accent)
                }
                Divider().padding(.leading, 12)
                settingsRow(L10n.t("launchLogin"), L10n.t("launchLogin.hint")) {
                    Toggle("", isOn: $state.launchAtLogin)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .tint(PinDockColor.accent)
                }
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    // MARK: - Permissions

    private var permissionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionLabel(L10n.t("pane.permissions"), systemImage: "hand.raised.fill")
            VStack(spacing: 0) {
                settingsRow(
                    L10n.t("accessibility"),
                    state.isTrusted ? L10n.t("accessibility.granted") : L10n.t("accessibility.required")
                ) {
                    if state.isTrusted {
                        Label(L10n.t("active"), systemImage: "checkmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.green)
                            .labelStyle(.titleAndIcon)
                    } else {
                        HStack(spacing: 6) {
                            Button(L10n.t("grant")) { state.openAccessibility() }
                                .buttonStyle(.borderedProminent)
                                .controlSize(.regular)
                            Button(L10n.t("retry")) { state.retryEngine() }
                                .controlSize(.regular)
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
            sectionLabel(L10n.t("pane.updates"), systemImage: "arrow.down.circle")
            VStack(spacing: 0) {
                settingsRow(L10n.t("autoCheck"), L10n.t("autoCheck.hint")) {
                    Toggle("", isOn: $state.autoCheckForUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .tint(PinDockColor.accent)
                }
                Divider().padding(.leading, 12)
                settingsRow(
                    L10n.t("autoInstall"),
                    state.autoCheckForUpdates
                        ? L10n.t("autoInstall.hint")
                        : L10n.t("autoInstall.needCheck")
                ) {
                    Toggle("", isOn: $state.autoInstallUpdates)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .controlSize(.small)
                        .tint(PinDockColor.accent)
                        .disabled(!state.autoCheckForUpdates)
                }
                Divider().padding(.leading, 12)
                settingsRow(L10n.t("status"), updateSubtitle) {
                    if state.isCheckingUpdate || state.isInstallingUpdate {
                        ProgressView().controlSize(.regular)
                    } else if state.updateAvailable {
                        HStack(spacing: 6) {
                            if state.updateDownloadURL != nil {
                                Button(L10n.t("install")) { state.installAvailableUpdate() }
                                    .buttonStyle(.borderedProminent)
                                    .controlSize(.regular)
                            }
                            Button(L10n.t("view")) { state.openReleasePage() }
                                .controlSize(.regular)
                        }
                    } else {
                        Button(L10n.t("check")) { state.checkForUpdates(force: true) }
                            .controlSize(.regular)
                    }
                }
            }
            .background(chipFill)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private var updateSubtitle: String {
        if state.isInstallingUpdate {
            return L10n.t("installing")
        }
        if state.updateAvailable, let v = state.latestRemoteVersion {
            return state.autoInstallUpdates ? L10n.t("versionAuto", v) : L10n.t("versionAvailable", v)
        }
        if !state.updateCheckIdleMessage.isEmpty {
            return state.updateCheckIdleMessage
        }
        return L10n.t("githubReleases")
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(L10n.t("version", state.appVersion))
                .font(.system(size: 10))
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 5) {
                Text(L10n.t("support"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                Text(L10n.t("support.hint"))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
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
            .background { PinDockCardFill() }
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
                Text(title)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
            trailing()
                .layoutPriority(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func sectionLabel(_ text: String, systemImage: String? = nil) -> some View {
        Group {
            if let systemImage {
                Label(text, systemImage: systemImage)
                    .labelStyle(.titleAndIcon)
            } else {
                Text(text)
            }
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.primary)
    }

    private var chipFill: some View {
        RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(colorScheme == .dark ? Color.white.opacity(0.10) : Color.black.opacity(0.08))
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
            .controlSize(.small)
            .tint(PinDockColor.accent)
            .help(isAllowed ? "Allowed" : "Blocked")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    Text(display.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                    if isDefault { pill(L10n.t("default"), PinDockColor.accent) }
                    if isActualDock { pill(L10n.t("dock"), PinDockColor.dock) }
                    if !isAllowed { pill(L10n.t("off"), Color(white: 0.55)) }
                }
                Text(display.isMain ? "\(L10n.t("main")) · \(sizeLabel)" : sizeLabel)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button(isDefault ? L10n.t("default") : L10n.t("setDefault")) {
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
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color)
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
                                    : isCurrent ? PinDockColor.dock.opacity(0.85)
                                    : isDefault ? PinDockColor.accent.opacity(0.30)
                                    : Color.primary.opacity(0.07)
                                )
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(
                                    blocked ? Color.secondary.opacity(0.3)
                                    : isCurrent ? PinDockColor.dock
                                    : isDefault ? PinDockColor.accent
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
                                    Text(L10n.t("dock"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(.white.opacity(0.9))
                                } else if isDefault {
                                    Text(L10n.t("default"))
                                        .font(.system(size: 10, weight: .semibold))
                                        .foregroundStyle(PinDockColor.accent)
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
