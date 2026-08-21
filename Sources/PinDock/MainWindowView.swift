import SwiftUI
import AppKit

/// Standalone app window — Settings.app style (sidebar + detail), not the menu-bar popover.
struct MainWindowView: View {
    @ObservedObject var state: AppState
    @State private var pane: WindowPane = .displays

    enum WindowPane: String, CaseIterable, Identifiable, Hashable {
        case displays
        case behavior
        case appearance
        case permissions
        case updates
        case about

        var id: String { rawValue }

        var title: String {
            switch self {
            case .displays: return "Displays"
            case .behavior: return "Behavior"
            case .appearance: return "Appearance"
            case .permissions: return "Permissions"
            case .updates: return "Updates"
            case .about: return "About"
            }
        }

        var symbol: String {
            switch self {
            case .displays: return "display.2"
            case .behavior: return "slider.horizontal.3"
            case .appearance: return "macwindow"
            case .permissions: return "hand.raised.fill"
            case .updates: return "arrow.down.circle"
            case .about: return "info.circle"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $pane) {
                Section("PinDock") {
                    ForEach(WindowPane.allCases) { item in
                        Label(item.title, systemImage: item.symbol)
                            .tag(item)
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 168, ideal: 196, max: 240)
        } detail: {
            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .navigationTitle(pane.title)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                HStack(spacing: 8) {
                    Text(state.statusLine)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(maxWidth: 280, alignment: .trailing)
                    Toggle(isOn: $state.isEnabled) {
                        Text("Pinning")
                    }
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .help(state.isEnabled ? "Pinning on" : "Pinning off")
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder
    private var detail: some View {
        switch pane {
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
            .padding(24)
            .frame(maxWidth: 720, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - Displays

    private var displaysPage: some View {
        page(title: "Displays", subtitle: "Choose where the Dock may live. Click a display to move it; Set default never moves the Dock by itself.") {
            if state.dockIsAway {
                HStack(alignment: .center, spacing: 12) {
                    Image(systemName: "arrow.uturn.backward.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dock is away from the default display")
                            .font(.system(size: 13, weight: .semibold))
                        Text("\(DisplayManager.shared.name(for: state.actualDockDisplayID != 0 ? state.actualDockDisplayID : state.currentDockDisplayID)) → \(DisplayManager.shared.name(for: state.defaultDisplayID))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Move Back") { state.moveBackToDefault() }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut("d", modifiers: [.command, .shift])
                }
                .padding(14)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Arrangement")
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
                .frame(height: 160)
                .padding(12)
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Allowed for Dock")
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
                .background(Color(nsColor: .controlBackgroundColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - Behavior

    private var behaviorPage: some View {
        page(title: "Behavior", subtitle: "How PinDock moves the Dock and what happens when you sign in or wake the Mac.") {
            Form {
                Section {
                    LabeledContent("Move Back") {
                        Text("⌘⇧D")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(.secondary)
                    }
                    Picker("Modifier at bottom edge", selection: $state.modifierKey) {
                        ForEach(ModifierKey.allCases) { key in
                            Text(key.shortLabel).tag(key)
                        }
                    }
                    Toggle("Restore on wake", isOn: $state.restoreOnWake)
                    Toggle("Launch at login", isOn: $state.launchAtLogin)
                } footer: {
                    Text("Hold the modifier at a display’s bottom edge to move the Dock on purpose. Restore on wake also runs when monitors are plugged in or unplugged.")
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Appearance

    private var appearancePage: some View {
        page(title: "Appearance", subtitle: "Choose menu bar, a standalone window, or both. The Dock lock works the same in every mode.") {
            Form {
                Section {
                    Picker("Show PinDock", selection: $state.appPresentation) {
                        ForEach(AppPresentation.allCases) { mode in
                            Text(mode.shortLabel).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                } footer: {
                    Text(state.appPresentation.subtitle)
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Permissions

    private var permissionsPage: some View {
        page(title: "Permissions", subtitle: "Accessibility is required to lock the Dock on the display you choose.") {
            if !state.isTrusted || (state.isEnabled && !state.isRunning) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.orange)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Accessibility needed")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Enable PinDock in System Settings → Privacy & Security → Accessibility, then Retry.")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 8) {
                            Button("Grant…") { state.openAccessibility() }
                                .buttonStyle(.borderedProminent)
                            Button("Retry") { state.retryEngine() }
                        }
                    }
                    Spacer()
                }
                .padding(16)
                .background(Color.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Form {
                Section {
                    LabeledContent("Accessibility") {
                        if state.isTrusted {
                            Label("Active", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        } else {
                            Text("Not granted")
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
        page(title: "Updates", subtitle: "Optional check against public GitHub Releases. Installs are verified (host, SHA-256, codesign).") {
            if state.updateAvailable {
                HStack(spacing: 12) {
                    Image(systemName: "arrow.down.circle.fill")
                        .font(.system(size: 22))
                        .foregroundStyle(Color.accentColor)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Version \(state.latestRemoteVersion ?? "") is available")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Downloaded from GitHub Releases and verified before install.")
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
                                Button("Install") { state.installAvailableUpdate() }
                                    .buttonStyle(.borderedProminent)
                            }
                            Button("View") { state.openReleasePage() }
                        }
                    }
                }
                .padding(16)
                .background(Color.accentColor.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            Form {
                Section {
                    Toggle("Auto check for updates", isOn: $state.autoCheckForUpdates)
                    Toggle("Auto install updates", isOn: $state.autoInstallUpdates)
                        .disabled(!state.autoCheckForUpdates)
                    LabeledContent("Status") {
                        if state.isCheckingUpdate || state.isInstallingUpdate {
                            ProgressView().controlSize(.small)
                        } else if state.updateAvailable {
                            Text(updateStatusLine)
                                .foregroundStyle(.secondary)
                        } else {
                            HStack(spacing: 8) {
                                Text(updateStatusLine)
                                    .foregroundStyle(.secondary)
                                Button("Check") { state.checkForUpdates(force: true) }
                            }
                        }
                    }
                } footer: {
                    Text("Auto check is off by default. Auto install only runs after verification.")
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
        if state.isInstallingUpdate { return "Installing…" }
        if state.updateAvailable, let v = state.latestRemoteVersion {
            return state.autoInstallUpdates ? "\(v) — auto install" : "\(v) available"
        }
        if !state.updateCheckIdleMessage.isEmpty { return state.updateCheckIdleMessage }
        return "GitHub Releases"
    }

    // MARK: - About

    private var aboutPage: some View {
        page(title: "About", subtitle: "Pin the macOS Dock to the display you choose. Free, offline, open source.") {
            HStack(alignment: .center, spacing: 16) {
                if let image = NSImage(named: "HeaderLogo") {
                    Image(nsImage: image)
                        .resizable()
                        .renderingMode(.template)
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 48, height: 48)
                        .foregroundStyle(.primary)
                } else {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 36))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("PinDock")
                        .font(.system(size: 20, weight: .semibold))
                    Text("Version \(state.appVersion)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.bottom, 8)

            Form {
                Section {
                    LabeledContent("Lightning") {
                        Link("j0b1t@strike.me", destination: URL(string: "https://strike.me/j0b1t")!)
                    }
                    LabeledContent("Ko‑fi") {
                        Link("ko-fi.com/j0b1t", destination: URL(string: "https://ko-fi.com/j0b1t")!)
                    }
                } header: {
                    Text("Support")
                } footer: {
                    Text("Optional tips never unlock features.")
                }
                Section {
                    LabeledContent("License") { Text("MIT") }
                    LabeledContent("Source") {
                        Link("github.com/j0b1t/PinDock", destination: URL(string: "https://github.com/j0b1t/PinDock")!)
                    }
                } header: {
                    Text("License")
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity)
        }
    }
}
