import SwiftUI
import ServiceManagement
import PerformanceAppCore

struct SettingsView: View {
    // Plain let — no @ObservedObject. Each child tab observes the SettingsStore
    // directly (not the engine), so the TabView (and its tab-bar SF Symbol
    // icons) is never re-rendered by engine ticks — and, since settings only
    // change on user action, the tabs no longer redraw on every metrics tick at
    // all. Appearance / dock changes are handled by SettingsWindowModifier.
    let engine: MetricsEngine
    let updater: UpdateChecker
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            GeneralTab(settings: engine.settings, launchAtLogin: $launchAtLogin)
                .tabItem { Label(String(localized: "General"), systemImage: "gearshape.fill") }

            MenuBarTab(settings: engine.settings)
                .tabItem { Label(String(localized: "Menu Bar"), systemImage: "menubar.rectangle") }

            MetricsTab(settings: engine.settings)
                .tabItem { Label(String(localized: "Metrics"), systemImage: "chart.bar.fill") }

            AlertsTab(alerts: engine.alerts)
                .tabItem { Label(String(localized: "Alerts"), systemImage: "bell.badge.fill") }

            PanelsTab(settings: engine.settings)
                .tabItem { Label(String(localized: "Panels"), systemImage: "square.grid.2x2") }

            HistoryTab(engine: engine, settings: engine.settings)
                .tabItem { Label(String(localized: "History"), systemImage: "clock.arrow.circlepath") }

            UpdatesTab(updater: updater, settings: engine.settings)
                .tabItem { Label(String(localized: "Updates"), systemImage: "arrow.down.circle.fill") }
        }
        .frame(width: 500)
        .background(.regularMaterial)
        .modifier(SettingsWindowModifier(settings: engine.settings))
        .transaction { $0.animation = nil }
    }
}

// Isolated observer for the two settings properties that affect window-level
// presentation. Keeps appearance and dock changes working without forcing
// the entire TabView to re-render on every metrics tick.
private struct SettingsWindowModifier: ViewModifier {
    @ObservedObject var settings: SettingsStore

    func body(content: Content) -> some View {
        content
            .background(WindowFocuser(settings: settings))
            .preferredColorScheme(settings.preferredColorScheme)
    }
}

// MARK: - Window focus helper

// Makes the Settings window key the moment it appears and resets the activation
// policy back to .accessory (for dock-hidden mode) when the window closes.
//
// The close observer is always registered and reads settings.showInDock live
// (rather than a value captured at makeNSView time), because makeNSView only
// runs once per window instance — if it only registered the observer when
// showInDock was false at first-open, toggling the setting later on the same
// window instance would leave the dock icon stuck.
private struct WindowFocuser: NSViewRepresentable {
    let settings: SettingsStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak settings] _ in
                Task { @MainActor in
                    guard let settings, !settings.showInDock else { return }
                    if !NSApp.hasOtherVisibleTitledWindow(besides: window) {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

// MARK: - General tab

private struct GeneralTab: View {
    @ObservedObject var settings: SettingsStore
    @Binding var launchAtLogin: Bool
    // Captured on first appearance so the relaunch banner shows only after
    // the user actually changes the language during this Settings visit —
    // not merely because a non-system language was already active.
    @State private var initialAppLanguage: AppLanguage?

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "gearshape.fill", title: String(localized: "General"), color: .gray) {
                SettingsRow(label: String(localized: "Refresh interval")) {
                    HStack(spacing: 8) {
                        Slider(value: $settings.refreshInterval, in: 0.5...5.0, step: 0.5)
                        Text(String(format: "%.1fs", settings.refreshInterval))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36)
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: String(localized: "Appearance")) {
                    Picker("", selection: $settings.appAppearance) {
                        ForEach(AppAppearance.allCases) { a in
                            Text(a.displayName).tag(a)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: String(localized: "Language")) {
                    Picker("", selection: $settings.appLanguage) {
                        ForEach(AppLanguage.allCases) { lang in
                            Text(lang.displayName).tag(lang)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                    .frame(width: 160)
                }
                if let initial = initialAppLanguage, settings.appLanguage != initial {
                    HStack(spacing: 8) {
                        Text(String(localized: "Takes effect after relaunch"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(String(localized: "Relaunch Now")) { relaunchApp() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: String(localized: "Show in Dock")) {
                    Toggle("", isOn: $settings.showInDock).labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: String(localized: "Launch at login")) {
                    Toggle("", isOn: $launchAtLogin)
                        .labelsHidden()
                        .onChange(of: launchAtLogin) { _, newValue in
                            do {
                                if newValue { try SMAppService.mainApp.register() }
                                else { try SMAppService.mainApp.unregister() }
                            } catch {
                                launchAtLogin = SMAppService.mainApp.status == .enabled
                            }
                        }
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: String(localized: "Open / close popover")) {
                    Text(ExtraMenuBarController.shortcutDisplay)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: String(localized: "Crash Reports")) {
                    Button(String(localized: "Open Crash Reports Folder")) {
                        let dir = CrashReporter.reportsDirectory
                        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(dir)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }

            SettingsSection(icon: "list.number", title: String(localized: "Processes"), color: .blue) {
                SettingsRow(label: String(localized: "Top processes shown")) {
                    Stepper(value: $settings.topProcessCount, in: 3...15) {
                        Text("\(settings.topProcessCount)")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                    }
                }
            }

            supportBlock
        }
        .padding(16)
        .transaction { $0.animation = nil }
        .onAppear {
            if initialAppLanguage == nil { initialAppLanguage = settings.appLanguage }
        }
    }

    /// Small, deliberately unobtrusive donation link — no banner, no popup.
    /// Ko-fi is the current outlet; a GitHub Sponsors link may be added
    /// alongside or in place of this once that application has been approved.
    private var supportBlock: some View {
        VStack(spacing: 2) {
            Button(String(localized: "Support this project ♥")) {
                NSWorkspace.shared.open(URL(string: "https://ko-fi.com/inequitas")!)
            }
            .buttonStyle(.link)
            .font(.caption2)
            Text(String(localized: "Performance Monitor is free and always will be."))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 2)
    }

    /// Relaunches the app so a language change (which macOS only picks up
    /// from AppleLanguages at process start) takes effect. Launches a fresh
    /// instance of the same bundle, then quits this one — NSWorkspace's
    /// openApplication is the modern, sandbox-safe replacement for spawning
    /// the executable directly via Process/NSTask.
    private func relaunchApp() {
        let bundleURL = Bundle.main.bundleURL
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: configuration) { _, _ in }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Menu Bar tab

private struct MenuBarTab: View {
    @ObservedObject var settings: SettingsStore
    @State private var dragging:    MenuBarMetric? = nil
    @State private var dragY:       CGFloat = 0
    @State private var dragSrc:     Int = 0
    @State private var dragDst:     Int = 0
    @State private var grabOffset:  CGFloat = 0  // mouse Y within the grabbed row at drag start

    private let rowH: CGFloat = 50

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.indigo.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: "menubar.rectangle")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.indigo)
                }
                .transaction { $0.animation = nil }
                Text(String(localized: "Menu Bar Icons")).font(.headline)
            }

            Text(String(localized: "Drag the handle to reorder. The topmost enabled icon appears rightmost in the menu bar."))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            SettingsRow(label: String(localized: "Colour when above alert threshold")) {
                Toggle("", isOn: $settings.menuBarThresholdColor).labelsHidden()
            }

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                ForEach(Array(settings.menuBarOrder.enumerated()), id: \.element) { i, metric in
                    let isMe = dragging == metric
                    HStack(spacing: 0) {
                        dragHandle(for: metric, at: i)
                        MenuBarMetricRow(metric: metric, settings: settings)
                    }
                    .frame(maxWidth: .infinity, minHeight: rowH, maxHeight: rowH)
                    .background(isMe ? Color.primary.opacity(0.07) : Color.clear,
                                in: RoundedRectangle(cornerRadius: 8))
                    .padding(.horizontal, 8)
                    .scaleEffect(isMe ? 1.015 : 1, anchor: .center)
                    .shadow(color: isMe ? .black.opacity(0.18) : .clear, radius: 6, y: 3)
                    .zIndex(isMe ? 1 : 0)
                    .offset(y: rowY(index: i, metric: metric))
                    .animation(isMe ? nil : .interactiveSpring(response: 0.28, dampingFraction: 0.78),
                               value: dragDst)
                }
            }
            .coordinateSpace(name: "menuBarList")
            .frame(maxWidth: .infinity)
            .frame(height: rowH * CGFloat(settings.menuBarOrder.count))
        }
        .padding(16)
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private func dragHandle(for metric: MenuBarMetric, at i: Int) -> some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .font(.system(size: 12))
            .frame(width: 28, height: rowH)
            .contentShape(Rectangle())
            .onHover { over in over ? NSCursor.openHand.push() : NSCursor.pop() }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named("menuBarList"))
                    .onChanged { v in
                        if dragging == nil {
                            dragging    = metric
                            dragSrc     = i
                            dragDst     = i
                            // Record where within the row the grab started so the
                            // item stays anchored to the grab point as it moves.
                            grabOffset  = v.startLocation.y - CGFloat(i) * rowH
                        }
                        // Position item so grab point stays under the mouse.
                        dragY = v.location.y - grabOffset - CGFloat(dragSrc) * rowH
                        // Slot = whichever row the mouse is currently over.
                        let nd = max(0, min(settings.menuBarOrder.count - 1,
                                           Int(v.location.y / rowH)))
                        if nd != dragDst {
                            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.78)) {
                                dragDst = nd
                            }
                        }
                    }
                    .onEnded { _ in
                        var order = settings.menuBarOrder
                        order.move(fromOffsets: IndexSet(integer: dragSrc),
                                   toOffset: dragDst > dragSrc ? dragDst + 1 : dragDst)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            settings.menuBarOrder = order
                            dragging = nil
                            dragY    = 0
                        }
                    }
            )
    }

    private func rowY(index i: Int, metric: MenuBarMetric) -> CGFloat {
        if dragging == metric { return CGFloat(dragSrc) * rowH + dragY }
        return CGFloat(i) * rowH + rowShift(i)
    }

    private func rowShift(_ i: Int) -> CGFloat {
        guard dragging != nil, i != dragSrc else { return 0 }
        if dragSrc < dragDst { return (i > dragSrc && i <= dragDst) ? -rowH : 0 }
        return (i >= dragDst && i < dragSrc) ? rowH : 0
    }
}

private struct MenuBarMetricRow: View {
    let metric: MenuBarMetric
    @ObservedObject var settings: SettingsStore

    private var enabled: Binding<Bool> {
        Binding(get: { settings.isEnabled(metric) },
                set: { settings.setEnabled($0, for: metric) })
    }

    private var style: Binding<MenuBarStyle> {
        Binding(get: { settings.styleFor(metric) },
                set: { settings.setStyle($0, for: metric) })
    }

    var body: some View {
        HStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 6)
                    .fill(metric.color.opacity(0.15))
                    .frame(width: 26, height: 26)
                Image(systemName: metric.icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(metric.color)
                    .symbolEffectsRemoved()
            }
            .transaction { $0.animation = nil }
            Text(metric.displayName).font(.callout)
            Spacer()
            if enabled.wrappedValue {
                // Disk: IO vs Space toggle
                if metric == .disk {
                    Picker("", selection: $settings.diskDisplayMode) {
                        Text(String(localized: "IO")).tag(MetricsEngine.DiskDisplayMode.io)
                        Text(String(localized: "Space")).tag(MetricsEngine.DiskDisplayMode.space)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 80)
                }

                // Sparkline metric picker — which series drives the graph
                if style.wrappedValue == .sparkline {
                    if metric == .network {
                        Picker("", selection: $settings.networkSparklineUpload) {
                            Text("↓").tag(false)
                            Text("↑").tag(true)
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 52)
                    } else if metric == .disk && settings.diskDisplayMode == .io {
                        Picker("", selection: $settings.diskSparklineWrite) {
                            Text("R").tag(false)
                            Text("W").tag(true)
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 52)
                    }
                }

                // Style picker — hidden for disk+space (always text)
                if !(metric == .disk && settings.diskDisplayMode == .space) {
                    Picker("", selection: style) {
                        Text(String(localized: "Text")).tag(MenuBarStyle.text)
                        Text(String(localized: "Graph")).tag(MenuBarStyle.sparkline)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 100)
                }
            }
            Toggle("", isOn: enabled).labelsHidden()
        }
    }
}

// MARK: - Updates tab

private struct UpdatesTab: View {
    @ObservedObject var updater: UpdateChecker
    @ObservedObject var settings: SettingsStore

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(spacing: 16) {
            if !updater.notificationsEnabled {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                        Text(String(localized: "Update notifications are disabled. Enable them in System Settings → Notifications → Performance Monitor."))
                            .font(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Spacer()
                        Button(String(localized: "Open Settings")) {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                        }
                        .buttonStyle(.bordered).controlSize(.small)
                    }
                }
                .padding(10)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.2), lineWidth: 1))
            }

            SettingsSection(icon: "arrow.down.circle.fill", title: String(localized: "Updates"), color: .blue) {
                SettingsRow(label: String(localized: "Current version")) {
                    HStack(spacing: 6) {
                        Text(updater.currentVersion)
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if updater.isBetaChannel {
                            Text(String(localized: "Beta channel"))
                                .font(.caption2.weight(.semibold))
                                .padding(.horizontal, 6).padding(.vertical, 2)
                                .background(.orange.opacity(0.15), in: Capsule())
                                .foregroundStyle(.orange)
                        }
                    }
                }
                Divider().padding(.vertical, 4)
                statusContent
                // The opt-in only makes sense on a stable build — an actual
                // beta build is already on the beta channel via its
                // Info.plist and shows the "Beta channel" badge above instead.
                if updater.channel != .beta {
                    Divider().padding(.vertical, 4)
                    SettingsRow(label: String(localized: "Also receive beta updates")) {
                        Toggle("", isOn: $settings.betaUpdatesOptIn).labelsHidden()
                    }
                    Text(String(localized: "Beta updates arrive sooner but are tested less."))
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                    switchToStableBlock
                }
                // Shown whenever this run is effectively on the beta channel
                // — an actual beta build, or a stable build with the opt-in
                // above enabled — since beta users are exactly the ones who
                // need an easy way to report problems.
                if updater.isBetaChannel {
                    betaWarning
                }
            }
        }
        .padding(16)
        .task { await updater.refreshNotificationStatus() }
    }

    private var betaWarning: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(String(localized: "Beta versions may contain bugs or unfinished features."))
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Button(String(localized: "Report a problem")) {
                NSWorkspace.shared.open(URL(string: "https://github.com/inequitas/performancemonitor/issues")!)
            }
            .buttonStyle(.link)
            .font(.caption2)
        }
        .padding(.top, 2)
    }

    /// Shown right under the opt-in toggle whenever it's off (whether the
    /// user just switched it off, or it was already off when the tab opened
    /// — e.g. after a restart) while the running version is a pre-release on
    /// an otherwise-stable build. Offers one click back onto stable using the
    /// same download/verify/install chain as a normal update.
    @ViewBuilder private var switchToStableBlock: some View {
        if updater.canSwitchToLatestStable && !settings.betaUpdatesOptIn {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "arrow.uturn.backward.circle")
                        .foregroundStyle(.blue)
                    Text(String(format: String(localized: "You're currently on a beta version (%@). You can switch back to the latest stable release now."), updater.currentVersion))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                switch updater.state {
                case .downloading:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "Downloading…")).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }
                case .installing:
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(String(localized: "Installing — app will restart shortly…")).font(.caption2).foregroundStyle(.secondary)
                        Spacer()
                    }
                case .error(let message):
                    VStack(alignment: .leading, spacing: 4) {
                        Text(message).font(.caption2).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Spacer()
                            Button(String(localized: "Switch to Stable Now")) { updater.switchToLatestStable() }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                    }
                default:
                    HStack {
                        Spacer()
                        Button(String(localized: "Switch to Stable Now")) { updater.switchToLatestStable() }
                            .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                Text(String(localized: "Your settings will be kept."))
                    .font(.caption2).foregroundStyle(.tertiary)
            }
            .padding(10)
            .background(.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.blue.opacity(0.2), lineWidth: 1))
            .padding(.top, 2)
        }
    }

    @ViewBuilder private var statusContent: some View {
        switch updater.state {
        case .idle:
            SettingsRow(label: "") { checkNowButton }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Checking for updates…")).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }.padding(.vertical, 3)

        case .upToDate:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(localized: "You're up to date")).font(.callout)
                    if let date = updater.lastChecked {
                        Text(String(format: String(localized: "Checked %@"), Self.relativeFormatter.localizedString(for: date, relativeTo: Date())))
                            .font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                checkNowButton
            }.padding(.vertical, 3)
            Divider().padding(.vertical, 4)
            snoozePicker

        case .available(let version, let url):
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: String(localized: "v%@ is available"), version)).font(.callout)
                    Text(String(localized: "The app will quit and relaunch after installing."))
                        .font(.caption2).foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(String(localized: "Update Now")) { updater.downloadAndInstall(from: url) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }.padding(.vertical, 3)
            Divider().padding(.vertical, 4)
            snoozePicker

        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Downloading…")).font(.callout).foregroundStyle(.secondary)
                Spacer()
            }.padding(.vertical, 3)

        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Installing — app will restart shortly…")).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
            }.padding(.vertical, 3)

        case .error(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(String(localized: "Try Again")) { updater.checkForUpdates() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Spacer()
            }.padding(.vertical, 3)
        }
    }

    private var checkNowButton: some View {
        Button(String(localized: "Check Now")) { updater.checkForUpdates() }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var snoozePicker: some View {
        SettingsRow(label: String(localized: "Remind me later after")) {
            Picker("", selection: $updater.snoozeDays) {
                Text(String(localized: "1 day")).tag(1)
                Text(String(localized: "3 days")).tag(3)
                Text(String(localized: "7 days")).tag(7)
                Text(String(localized: "14 days")).tag(14)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 100)
        }
    }
}

// MARK: - Metrics tab

private struct MetricsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "internaldrive", title: String(localized: "Disk"), color: .indigo) {
                SettingsRow(label: String(localized: "Show removable volumes")) {
                    Toggle("", isOn: $settings.showRemovableVolumes).labelsHidden()
                }
            }

            SettingsSection(icon: "network", title: String(localized: "Network"), color: .green) {
                SettingsRow(label: String(localized: "Show public IP")) {
                    Toggle("", isOn: $settings.publicIPEnabled).labelsHidden()
                }
                if settings.publicIPEnabled {
                    Text(String(localized: "Fetches from api.ipify.org over HTTPS every 5 min."))
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: String(localized: "Ping server")) {
                    Picker("", selection: $settings.pingServer) {
                        ForEach(MetricsEngine.PingServer.allCases) { server in
                            Text(server.displayName).tag(server)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 180)
                }
            }
        }
        .padding(16)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Alerts tab

private struct AlertsTab: View {
    @ObservedObject var alerts: AlertService

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "bell.badge.fill", title: String(localized: "Alerts"), color: .orange) {
                SettingsRow(label: String(localized: "Enable notifications")) {
                    Toggle("", isOn: $alerts.alertsEnabled).labelsHidden()
                }
                if alerts.alertsEnabled {
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "cpu", label: String(localized: "CPU above"),
                        color: MetricTheme.cpu,
                        enabled: $alerts.cpuEnabled,
                        value: $alerts.cpuThreshold,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "memorychip", label: String(localized: "Memory above"),
                        color: MetricTheme.memory,
                        enabled: $alerts.memoryEnabled,
                        value: $alerts.memoryThresholdPercent,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "internaldrive", label: String(localized: "Disk free below"),
                        color: MetricTheme.disk,
                        enabled: $alerts.diskEnabled,
                        value: $alerts.diskFreeThresholdGB,
                        range: 1...50, step: 1, format: "%.0f GB"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "cube.transparent", label: String(localized: "GPU above"),
                        color: .cyan,
                        enabled: $alerts.gpuEnabled,
                        value: $alerts.gpuThreshold,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    SettingsRow(label: String(localized: "Thermal pressure")) {
                        Toggle("", isOn: $alerts.thermalEnabled).labelsHidden()
                    }
                    Divider().padding(.vertical, 4)
                    SettingsRow(label: String(localized: "Alert after exceeded for")) {
                        Picker("", selection: $alerts.alertSustainSeconds) {
                            Text(String(localized: "Off")).tag(0.0)
                            Text("10s").tag(10.0)
                            Text("30s").tag(30.0)
                            Text(String(localized: "1 min")).tag(60.0)
                            Text(String(localized: "2 min")).tag(120.0)
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 100)
                    }
                    Text(String(localized: "Applies to CPU, GPU and memory. Disk space and thermal alerts always fire immediately."))
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(String(localized: "Thermal alerts fire on Serious or Critical. All alerts are rate-limited to once per 5 min."))
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(16)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Panels tab

private struct PanelsTab: View {
    @ObservedObject var settings: SettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(String(localized: "Drag cards to reorder. Tap the eye to show or hide."))
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)

            PanelGridPreview(
                panelOrder: $settings.panelOrder,
                hiddenPanels: $settings.hiddenPanels
            )
        }
        .padding(16)
        .transaction { $0.animation = nil }
    }
}

private struct PanelGridPreview: View {
    @Binding var panelOrder:   [MetricsEngine.Panel]
    @Binding var hiddenPanels: Set<MetricsEngine.Panel>
    @State private var dragTarget: MetricsEngine.Panel? = nil
    @State private var clearTask:  Task<Void, Never>? = nil

    private var rows: [MetricsEngine.PanelRow] { MetricsEngine.panelLayout(panelOrder) }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows) { row in
                if let full = row.full {
                    card(full, fullWidth: true)
                } else {
                    HStack(spacing: 6) {
                        if let a = row.first  { card(a, fullWidth: false) }
                        if let b = row.second { card(b, fullWidth: false) }
                        else                  { Color.clear.frame(height: 58) }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func card(_ panel: MetricsEngine.Panel, fullWidth: Bool) -> some View {
        PanelMiniCard(
            panel: panel, fullWidth: fullWidth,
            hidden: hiddenPanels.contains(panel),
            isTarget: dragTarget == panel,
            panelOrder: $panelOrder, hiddenPanels: $hiddenPanels
        ) { over in
            if over {
                // Cancel any pending clear so transitioning between cards is seamless
                clearTask?.cancel()
                clearTask = nil
                withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.78)) {
                    dragTarget = panel
                }
            } else {
                // Delay the clear so the next card's entry can cancel it first,
                // preventing a one-frame flicker as the drag crosses card boundaries.
                clearTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 80_000_000)
                    guard !Task.isCancelled else { return }
                    withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.78)) {
                        if dragTarget == panel { dragTarget = nil }
                    }
                }
            }
        }
    }
}

private struct PanelMiniCard: View {
    let panel:      MetricsEngine.Panel
    let fullWidth:  Bool
    let hidden:     Bool
    let isTarget:   Bool
    @Binding var panelOrder:   [MetricsEngine.Panel]
    @Binding var hiddenPanels: Set<MetricsEngine.Panel>
    let onTargeted: (Bool) -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                Image(systemName: panel.icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hidden ? .secondary : panel.color)
                    .symbolEffectsRemoved()
                Text(panel.title)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(hidden ? .tertiary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTarget ? panel.color.opacity(0.25) :
                          hidden ? Color.primary.opacity(0.04) : panel.color.opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isTarget ? panel.color :
                                  panel.color.opacity(hidden ? 0.1 : 0.3), lineWidth: isTarget ? 2 : 1)
            )
            .opacity(hidden ? 0.45 : 1)
            .scaleEffect(isTarget ? 1.04 : 1, anchor: .center)
            .animation(.interactiveSpring(response: 0.25, dampingFraction: 0.78), value: isTarget)

            Button {
                if hidden { hiddenPanels.remove(panel) } else { hiddenPanels.insert(panel) }
            } label: {
                Image(systemName: hidden ? "eye.slash" : "eye")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(4)
            }
            .buttonStyle(.plain)
        }
        .draggable(panel)
        .dropDestination(for: MetricsEngine.Panel.self) { dropped, _ in
            guard let source = dropped.first, source != panel,
                  let from = panelOrder.firstIndex(of: source),
                  let to   = panelOrder.firstIndex(of: panel) else { return false }
            var order = panelOrder
            order.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) { panelOrder = order }
            return true
        } isTargeted: { onTargeted($0) }
    }
}


// MARK: - History tab

private struct HistoryTab: View {
    let engine: MetricsEngine
    @ObservedObject var settings: SettingsStore
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "clock.arrow.circlepath", title: String(localized: "History"), color: .purple) {
                SettingsRow(label: String(localized: "Save history to disk")) {
                    Toggle("", isOn: $settings.persistHistoryEnabled).labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: String(localized: "History")) {
                    Button(String(localized: "Open History Window")) {
                        NSApp.setActivationPolicy(.regular)
                        NSApp.activate(ignoringOtherApps: true)
                        openWindow(id: "history")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
                if settings.persistHistoryEnabled {
                    Divider().padding(.vertical, 4)
                    SettingsRow(label: String(localized: "Export")) {
                        Button(String(localized: "Export CSV…")) { engine.exportHistoryCSV() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(16)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Reusable section container

private struct SettingsSection<Content: View>: View {
    let icon: String
    let title: String
    let color: Color
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color.opacity(0.18))
                        .frame(width: 28, height: 28)
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(color)
                        .symbolEffectsRemoved()
                }
                .transaction { $0.animation = nil }
                Text(title).font(.headline)
            }

            VStack(alignment: .leading, spacing: 0) {
                content()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
        }
        .transaction { $0.animation = nil }
    }
}

// MARK: - Row layout

private struct SettingsRow<Control: View>: View {
    let label: String
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack {
            Text(label).font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            control()
        }
        .padding(.vertical, 3)
    }
}

private struct AlertMetricRow: View {
    let icon: String
    let label: String
    let color: Color
    @Binding var enabled: Bool
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let format: String

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(color)
                    .frame(width: 16)
                Text(label).font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Toggle("", isOn: $enabled).labelsHidden()
            }
            if enabled {
                HStack(spacing: 8) {
                    Slider(value: $value, in: range, step: step)
                    Text(String(format: format, value))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 44, alignment: .trailing)
                }
                .padding(.leading, 24)
            }
        }
        .padding(.vertical, 3)
    }
}
