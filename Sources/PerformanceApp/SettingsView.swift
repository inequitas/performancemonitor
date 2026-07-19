import SwiftUI
import ServiceManagement
import PerformanceAppCore

struct SettingsView: View {
    // Plain let — no @ObservedObject. Each child tab observes engine directly,
    // so the TabView (and its tab-bar SF Symbol icons) is never re-rendered by
    // engine ticks. Appearance / dock changes are handled by SettingsWindowModifier.
    let engine: MetricsEngine
    let updater: UpdateChecker
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            GeneralTab(engine: engine, launchAtLogin: $launchAtLogin)
                .tabItem { Label("General", systemImage: "gearshape.fill") }

            MenuBarTab(engine: engine)
                .tabItem { Label("Menu Bar", systemImage: "menubar.rectangle") }

            MetricsTab(engine: engine)
                .tabItem { Label("Metrics", systemImage: "chart.bar.fill") }

            AlertsTab(engine: engine)
                .tabItem { Label("Alerts", systemImage: "bell.badge.fill") }

            PanelsTab(engine: engine)
                .tabItem { Label("Panels", systemImage: "square.grid.2x2") }

            HistoryTab(engine: engine)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }

            UpdatesTab(updater: updater)
                .tabItem { Label("Updates", systemImage: "arrow.down.circle.fill") }
        }
        .frame(width: 420)
        .background(.regularMaterial)
        .modifier(SettingsWindowModifier(engine: engine))
        .transaction { $0.animation = nil }
    }
}

// Isolated observer for the two engine properties that affect window-level
// presentation. Keeps appearance and dock changes working without forcing
// the entire TabView to re-render on every metrics tick.
private struct SettingsWindowModifier: ViewModifier {
    @ObservedObject var engine: MetricsEngine

    func body(content: Content) -> some View {
        content
            .background(WindowFocuser(engine: engine))
            .preferredColorScheme(engine.preferredColorScheme)
    }
}

// MARK: - Window focus helper

// Makes the Settings window key the moment it appears and resets the activation
// policy back to .accessory (for dock-hidden mode) when the window closes.
//
// The close observer is always registered and reads engine.showInDock live
// (rather than a value captured at makeNSView time), because makeNSView only
// runs once per window instance — if it only registered the observer when
// showInDock was false at first-open, toggling the setting later on the same
// window instance would leave the dock icon stuck.
private struct WindowFocuser: NSViewRepresentable {
    let engine: MetricsEngine

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
            ) { [weak engine] _ in
                Task { @MainActor in
                    guard let engine, !engine.showInDock else { return }
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
    @ObservedObject var engine: MetricsEngine
    @Binding var launchAtLogin: Bool

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "gearshape.fill", title: "General", color: .gray) {
                SettingsRow(label: "Refresh interval") {
                    HStack(spacing: 8) {
                        Slider(value: $engine.refreshInterval, in: 0.5...5.0, step: 0.5)
                        Text(String(format: "%.1fs", engine.refreshInterval))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 36)
                    }
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: "Appearance") {
                    Picker("", selection: $engine.appAppearance) {
                        ForEach(MetricsEngine.AppAppearance.allCases) { a in
                            Text(a.rawValue).tag(a)
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: "Show in Dock") {
                    Toggle("", isOn: $engine.showInDock).labelsHidden()
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: "Launch at login") {
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
                SettingsRow(label: "Open / close popover") {
                    Text(ExtraMenuBarController.shortcutDisplay)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                }
            }

            SettingsSection(icon: "list.number", title: "Processes", color: .blue) {
                SettingsRow(label: "Top processes shown") {
                    Stepper(value: $engine.topProcessCount, in: 3...15) {
                        Text("\(engine.topProcessCount)")
                            .font(.system(.body, design: .rounded).weight(.semibold))
                    }
                }
            }
        }
        .padding(16)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Menu Bar tab

private struct MenuBarTab: View {
    @ObservedObject var engine: MetricsEngine
    @State private var dragging:    MetricsEngine.MenuBarMetric? = nil
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
                Text("Menu Bar Icons").font(.headline)
            }

            Text("Drag the handle to reorder. The topmost enabled icon appears rightmost in the menu bar.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 14).fill(.ultraThinMaterial)
                ForEach(Array(engine.menuBarOrder.enumerated()), id: \.element) { i, metric in
                    let isMe = dragging == metric
                    HStack(spacing: 0) {
                        dragHandle(for: metric, at: i)
                        MenuBarMetricRow(metric: metric, engine: engine)
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
            .frame(height: rowH * CGFloat(engine.menuBarOrder.count))
        }
        .padding(16)
        .transaction { $0.animation = nil }
    }

    @ViewBuilder
    private func dragHandle(for metric: MetricsEngine.MenuBarMetric, at i: Int) -> some View {
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
                        let nd = max(0, min(engine.menuBarOrder.count - 1,
                                           Int(v.location.y / rowH)))
                        if nd != dragDst {
                            withAnimation(.interactiveSpring(response: 0.28, dampingFraction: 0.78)) {
                                dragDst = nd
                            }
                        }
                    }
                    .onEnded { _ in
                        var order = engine.menuBarOrder
                        order.move(fromOffsets: IndexSet(integer: dragSrc),
                                   toOffset: dragDst > dragSrc ? dragDst + 1 : dragDst)
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                            engine.menuBarOrder = order
                            dragging = nil
                            dragY    = 0
                        }
                    }
            )
    }

    private func rowY(index i: Int, metric: MetricsEngine.MenuBarMetric) -> CGFloat {
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
    let metric: MetricsEngine.MenuBarMetric
    @ObservedObject var engine: MetricsEngine

    private var enabled: Binding<Bool> {
        Binding(get: { engine.isEnabled(metric) },
                set: { engine.setEnabled($0, for: metric) })
    }

    private var style: Binding<MetricsEngine.MenuBarStyle> {
        Binding(get: { engine.styleFor(metric) },
                set: { engine.setStyle($0, for: metric) })
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
            Text(metric.rawValue).font(.callout)
            Spacer()
            if enabled.wrappedValue {
                // Disk: IO vs Space toggle
                if metric == .disk {
                    Picker("", selection: $engine.diskDisplayMode) {
                        Text("IO").tag(MetricsEngine.DiskDisplayMode.io)
                        Text("Space").tag(MetricsEngine.DiskDisplayMode.space)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 80)
                }

                // Sparkline metric picker — which series drives the graph
                if style.wrappedValue == .sparkline {
                    if metric == .network {
                        Picker("", selection: $engine.networkSparklineUpload) {
                            Text("↓").tag(false)
                            Text("↑").tag(true)
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 52)
                    } else if metric == .disk && engine.diskDisplayMode == .io {
                        Picker("", selection: $engine.diskSparklineWrite) {
                            Text("R").tag(false)
                            Text("W").tag(true)
                        }
                        .labelsHidden().pickerStyle(.segmented).frame(width: 52)
                    }
                }

                // Style picker — hidden for disk+space (always text)
                if !(metric == .disk && engine.diskDisplayMode == .space) {
                    Picker("", selection: style) {
                        Text("Text").tag(MetricsEngine.MenuBarStyle.text)
                        Text("Graph").tag(MetricsEngine.MenuBarStyle.sparkline)
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

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .full
        return f
    }()

    var body: some View {
        VStack(spacing: 16) {
            if !updater.notificationsEnabled {
                HStack(spacing: 8) {
                    Image(systemName: "bell.slash.fill").foregroundStyle(.orange)
                    Text("Update notifications are disabled. Enable them in System Settings → Notifications → Performance Monitor.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.notifications")!)
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .padding(10)
                .background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.orange.opacity(0.2), lineWidth: 1))
            }

            SettingsSection(icon: "arrow.down.circle.fill", title: "Updates", color: .blue) {
                SettingsRow(label: "Current version") {
                    Text(updater.currentVersion)
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Divider().padding(.vertical, 4)
                statusContent
            }
        }
        .padding(16)
        .task { await updater.refreshNotificationStatus() }
    }

    @ViewBuilder private var statusContent: some View {
        switch updater.state {
        case .idle:
            SettingsRow(label: "") { checkNowButton }

        case .checking:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Checking for updates…").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }.padding(.vertical, 3)

        case .upToDate:
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                VStack(alignment: .leading, spacing: 2) {
                    Text("You're up to date").font(.callout)
                    if let date = updater.lastChecked {
                        Text("Checked \(Self.relativeFormatter.localizedString(for: date, relativeTo: Date()))")
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
                    Text("v\(version) is available").font(.callout)
                    Text("The app will quit and relaunch after installing.")
                        .font(.caption2).foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Update Now") { updater.downloadAndInstall(from: url) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }.padding(.vertical, 3)
            Divider().padding(.vertical, 4)
            snoozePicker

        case .downloading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Downloading…").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }.padding(.vertical, 3)

        case .installing:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Installing — app will restart shortly…").font(.callout).foregroundStyle(.secondary)
                Spacer()
            }.padding(.vertical, 3)

        case .error(let message):
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(message).font(.callout).foregroundStyle(.secondary)
                    Button("Try Again") { updater.checkForUpdates() }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                Spacer()
            }.padding(.vertical, 3)
        }
    }

    private var checkNowButton: some View {
        Button("Check Now") { updater.checkForUpdates() }
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    private var snoozePicker: some View {
        SettingsRow(label: "Remind me later after") {
            Picker("", selection: $updater.snoozeDays) {
                Text("1 day").tag(1)
                Text("3 days").tag(3)
                Text("7 days").tag(7)
                Text("14 days").tag(14)
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .frame(maxWidth: 100)
        }
    }
}

// MARK: - Metrics tab

private struct MetricsTab: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "internaldrive", title: "Disk", color: .indigo) {
                SettingsRow(label: "Show removable volumes") {
                    Toggle("", isOn: $engine.showRemovableVolumes).labelsHidden()
                }
            }

            SettingsSection(icon: "network", title: "Network", color: .green) {
                SettingsRow(label: "Show public IP") {
                    Toggle("", isOn: $engine.publicIPEnabled).labelsHidden()
                }
                if engine.publicIPEnabled {
                    Text("Fetches from api.ipify.org over HTTPS every 5 min.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 2)
                }
                Divider().padding(.vertical, 4)
                SettingsRow(label: "Ping server") {
                    Picker("", selection: $engine.pingServer) {
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
    @ObservedObject var engine: MetricsEngine
    @ObservedObject private var alerts: AlertService

    init(engine: MetricsEngine) {
        self.engine = engine
        self.alerts = engine.alerts
    }

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "bell.badge.fill", title: "Alerts", color: .orange) {
                SettingsRow(label: "Enable notifications") {
                    Toggle("", isOn: $alerts.alertsEnabled).labelsHidden()
                }
                if alerts.alertsEnabled {
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "cpu", label: "CPU above",
                        color: MetricTheme.cpu,
                        enabled: $alerts.cpuEnabled,
                        value: $alerts.cpuThreshold,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "memorychip", label: "Memory above",
                        color: MetricTheme.memory,
                        enabled: $alerts.memoryEnabled,
                        value: $alerts.memoryThresholdPercent,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "internaldrive", label: "Disk free below",
                        color: MetricTheme.disk,
                        enabled: $alerts.diskEnabled,
                        value: $alerts.diskFreeThresholdGB,
                        range: 1...50, step: 1, format: "%.0f GB"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "cube.transparent", label: "GPU above",
                        color: .cyan,
                        enabled: $alerts.gpuEnabled,
                        value: $alerts.gpuThreshold,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    SettingsRow(label: "Thermal pressure") {
                        Toggle("", isOn: $alerts.thermalEnabled).labelsHidden()
                    }
                    Text("Thermal alerts fire on Serious or Critical. All alerts are rate-limited to once per 5 min.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
        }
        .padding(16)
        .transaction { $0.animation = nil }
    }
}

// MARK: - Panels tab

private struct PanelsTab: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Drag cards to reorder. Tap the eye to show or hide.")
                .font(.caption).foregroundStyle(.secondary)
                .padding(.horizontal, 2)

            PanelGridPreview(
                panelOrder: $engine.panelOrder,
                hiddenPanels: $engine.hiddenPanels
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
                Text(panel.rawValue)
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
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "clock.arrow.circlepath", title: "History", color: .purple) {
                SettingsRow(label: "Save history to disk") {
                    Toggle("", isOn: $engine.persistHistoryEnabled).labelsHidden()
                }
                if engine.persistHistoryEnabled {
                    Divider().padding(.vertical, 4)
                    SettingsRow(label: "Export") {
                        Button("Export CSV…") { engine.exportHistoryCSV() }
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
