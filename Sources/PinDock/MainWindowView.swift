import SwiftUI
import AppKit

/// Standalone app window — Settings.app style (sidebar + detail), not the menu-bar popover.
struct MainWindowView: View {
    @ObservedObject var state: AppState
    @State private var pane: WindowPane = .general

    enum WindowPane: String, CaseIterable, Identifiable, Hashable {
        case general
        case displays
        case behavior
        case appearance
        case permissions
        case updates
        case about

        var id: String { rawValue }

        var titleKey: String {
            switch self {
            case .general: return "pane.general"
            case .displays: return "pane.displays"
            case .behavior: return "pane.behavior"
            case .appearance: return "pane.appearance"
            case .permissions: return "pane.permissions"
            case .updates: return "pane.updates"
            case .about: return "pane.about"
            }
        }

        var title: String { L10n.t(titleKey) }

        var symbol: String {
            switch self {
            case .general: return "pin.fill"
            case .displays: return "display.2"
            case .behavior: return "slider.horizontal.3"
            case .appearance: return "macwindow"
            case .permissions: return "hand.raised.fill"
            case .updates: return "arrow.down.circle"
            case .about: return "info.circle"
            }
        }
    }

    @State private var sidebarExpanded = true

    private var sidebarWidth: CGFloat { sidebarExpanded ? 200 : 56 }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            sidebar
                .frame(width: sidebarWidth)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(10)
        .background { windowGlass }
        .frame(minWidth: 560, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                HStack(spacing: 10) {
                    Button {
                        sidebarExpanded.toggle()
                    } label: {
                        Image(systemName: "sidebar.leading")
                            .font(.system(size: 15, weight: .medium))
                            .frame(width: 22, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(sidebarExpanded ? L10n.t("sidebar.hide") : L10n.t("sidebar.show"))

                    Rectangle()
                        .fill(Color.primary.opacity(0.18))
                        .frame(width: 1, height: 18)

                    PinDockAppIcon(size: 26)
                    Text("PinDock")
                        .font(.system(size: 15, weight: .semibold))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            ToolbarItem(placement: .automatic) {
                PinDockStatusChip(state: state)
            }
        }
        .toolbarBackground(.visible, for: .windowToolbar)
        .toolbarBackground(.ultraThinMaterial, for: .windowToolbar)
        .background(
            GeometryReader { geo in
                Color.clear
                    .onChange(of: geo.size.width) { width in
                        if width < 680 {
                            sidebarExpanded = false
                        }
                    }
            }
        )
        .id(state.appLanguage)
        .animation(.easeInOut(duration: 0.15), value: sidebarExpanded)
    }

    private var windowGlass: some View {
        PinDockGlass()
    }

    private var sidebar: some View {
        List(selection: $pane) {
            ForEach(WindowPane.allCases) { item in
                Group {
                    if sidebarExpanded {
                        Label {
                            Text(item.title)
                        } icon: {
                            if item == .general {
                                PinDockMark(size: 15)
                            } else {
                                Image(systemName: item.symbol)
                            }
                        }
                    } else {
                        Group {
                            if item == .general {
                                PinDockMark(size: 16)
                            } else {
                                Image(systemName: item.symbol)
                                    .font(.system(size: 14, weight: .medium))
                            }
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .tag(item)
                .help(item.title)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .listRowSeparator(.hidden)
        .background(.ultraThinMaterial)
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
        case .general: generalPage
        case .displays: displaysPage
        case .behavior: behaviorPage
        case .appearance: appearancePage
        case .permissions: permissionsPage
        case .updates: updatesPage
        case .about: aboutPage
        }
    }

    private func page<Content: View>(title: String, subtitle: String, @ViewBuilder content: () -> Content) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.system(size: 22, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                content()
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - General / enable

    private var generalPage: some View {
        page(title: L10n.t("pane.general"), subtitle: L10n.t("general.subtitle")) {
            Form {
                Section {
                    Toggle(L10n.t("enable"), isOn: $state.isEnabled)
                    LabeledContent(L10n.t("status")) {
                        Text(state.statusLine)
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text(L10n.t("enable.hint"))
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Displays

    private var displaysPage: some View {
        page(title: L10n.t("pane.displays"), subtitle: L10n.t("displays.subtitle")) {
            if state.dockIsAway {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("dockAway.body"))
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(DisplayManager.shared.name(for: state.actualDockDisplayID != 0 ? state.actualDockDisplayID : state.currentDockDisplayID)) → \(DisplayManager.shared.name(for: state.defaultDisplayID))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button(L10n.t("moveBack")) { state.moveBackToDefault() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                }
                .padding(14)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.t("arrangement"), systemImage: "display.2")
                    .font(.system(size: 13, weight: .semibold))
                DisplayMapView(
                    displays: state.displays,
                    defaultID: state.defaultDisplayID,
                    actualDockID: state.actualDockDisplayID,
                    acquiringID: 0,
                    blockedIDs: state.blockedDisplayIDs
                ) { id in
                    state.moveDockToDisplay(id)
                }
                .frame(height: 180)
                .padding(12)
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.t("allowed"), systemImage: "checkmark.circle")
                    .font(.system(size: 13, weight: .semibold))
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
                .background(.thinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - Behavior

    private var behaviorPage: some View {
        page(title: L10n.t("pane.behavior"), subtitle: L10n.t("behavior.subtitle")) {
            Form {
                Section {
                    LabeledContent(L10n.t("moveBack")) {
                        Text("⌘⇧D")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Picker(L10n.t("modifier"), selection: $state.modifierKey) {
                        ForEach(ModifierKey.allCases) { key in
                            Text(key.localizedLabel).tag(key)
                        }
                    }
                    Toggle(L10n.t("restoreWake"), isOn: $state.restoreOnWake)
                    Toggle(L10n.t("launchLogin"), isOn: $state.launchAtLogin)
                } footer: {
                    Text(L10n.t("modifier.hint"))
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Appearance

    private var appearancePage: some View {
        page(title: L10n.t("pane.appearance"), subtitle: L10n.t("appearance.subtitle")) {
            Form {
                Section {
                    Picker(L10n.t("showPinDock"), selection: $state.appPresentation) {
                        Text(L10n.t("present.menuBar")).tag(AppPresentation.menuBar)
                        Text(L10n.t("present.window")).tag(AppPresentation.window)
                        Text(L10n.t("present.both")).tag(AppPresentation.both)
                    }
                    .pickerStyle(.radioGroup)
                } footer: {
                    Text(state.appPresentation.localizedSubtitle)
                }
                Section {
                    Picker(L10n.t("language"), selection: $state.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                } footer: {
                    Text(L10n.t("language.hint"))
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Permissions

    private var permissionsPage: some View {
        page(title: L10n.t("pane.permissions"), subtitle: L10n.t("permissions.subtitle")) {
            if !state.isTrusted || (state.isEnabled && !state.isRunning) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text(L10n.t("accessibility.needed"))
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.t("accessibility.body"))
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button(L10n.t("grant")) { state.openAccessibility() }
                                .buttonStyle(.borderedProminent)
                            Button(L10n.t("retry")) { state.retryEngine() }
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Form {
                Section {
                    LabeledContent(L10n.t("accessibility")) {
                        if state.isTrusted {
                            Label(L10n.t("active"), systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text(L10n.t("notGranted"))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Updates

    private var updatesPage: some View {
        page(title: L10n.t("pane.updates"), subtitle: L10n.t("updates.subtitle")) {
            if state.updateAvailable {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(L10n.t("update.ready", state.latestRemoteVersion ?? ""))
                            .font(.system(size: 14, weight: .semibold))
                        Text(L10n.t("update.ready.body"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if state.isInstallingUpdate {
                        ProgressView(value: state.updateProgress)
                            .frame(width: 90)
                    } else {
                        HStack(spacing: 8) {
                            if state.updateDownloadURL != nil {
                                Button(L10n.t("install")) { state.installAvailableUpdate() }
                                    .buttonStyle(.borderedProminent)
                            }
                            Button(L10n.t("view")) { state.openReleasePage() }
                        }
                    }
                }
                .padding(16)
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Form {
                Section {
                    Toggle(L10n.t("autoCheck"), isOn: $state.autoCheckForUpdates)
                    Toggle(L10n.t("autoInstall"), isOn: $state.autoInstallUpdates)
                        .disabled(!state.autoCheckForUpdates)
                    LabeledContent(L10n.t("status")) {
                        if state.isCheckingUpdate || state.isInstallingUpdate {
                            ProgressView().controlSize(.small)
                        } else if state.updateAvailable {
                            Text(updateStatusLine)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 8) {
                                Text(updateStatusLine)
                                    .foregroundStyle(.secondary)
                                Button(L10n.t("check")) { state.checkForUpdates(force: true) }
                            }
                        }
                    }
                } footer: {
                    Text(L10n.t("updates.footer"))
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)

            if !state.updateErrorMessage.isEmpty {
                Text(state.updateErrorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
    }

    private var updateStatusLine: String {
        if state.isInstallingUpdate { return L10n.t("installing") }
        if state.updateAvailable, let v = state.latestRemoteVersion {
            return state.autoInstallUpdates ? L10n.t("versionAuto", v) : L10n.t("versionAvailable", v)
        }
        if !state.updateCheckIdleMessage.isEmpty { return state.updateCheckIdleMessage }
        return L10n.t("githubReleases")
    }

    // MARK: - About

    private var aboutPage: some View {
        page(title: L10n.t("pane.about"), subtitle: L10n.t("about.subtitle")) {
            HStack(alignment: .center, spacing: 16) {
                PinDockMark(size: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text("PinDock")
                        .font(.system(size: 20, weight: .semibold))
                    Text(L10n.t("version", state.appVersion))
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 8)

            Form {
                Section {
                    LabeledContent(L10n.t("lightning")) {
                        Link("j0b1t@strike.me", destination: URL(string: "https://strike.me/j0b1t")!)
                    }
                    LabeledContent(L10n.t("kofi")) {
                        Link("ko-fi.com/j0b1t", destination: URL(string: "https://ko-fi.com/j0b1t")!)
                    }
                } header: {
                    Text(L10n.t("support"))
                } footer: {
                    Text(L10n.t("support.hint"))
                }
                Section {
                    LabeledContent(L10n.t("license")) { Text("MIT") }
                    LabeledContent(L10n.t("source")) {
                        Link("github.com/j0b1t/PinDock", destination: URL(string: "https://github.com/j0b1t/PinDock")!)
                    }
                } header: {
                    Text(L10n.t("license"))
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
    }
}

extension AppPresentation {
    var localizedLabel: String {
        switch self {
        case .menuBar: return L10n.t("present.menuBar")
        case .window: return L10n.t("present.window")
        case .both: return L10n.t("present.both")
        }
    }

    var localizedSubtitle: String {
        switch self {
        case .menuBar: return L10n.t("present.menuBar.hint")
        case .window: return L10n.t("present.window.hint")
        case .both: return L10n.t("present.both.hint")
        }
    }
}

extension ModifierKey {
    var localizedLabel: String {
        switch self {
        case .none: return L10n.t("none")
        default: return shortLabel
        }
    }
}
