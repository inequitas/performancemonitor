import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var engine: MetricsEngine
    @ObservedObject var updater: UpdateChecker
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        TabView {
            GeneralTab(engine: engine, launchAtLogin: $launchAtLogin)
                .tabItem { Label("General", systemImage: "gearshape.fill") }

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
        .background(WindowFocuser(showInDock: engine.showInDock))
    }
}

// MARK: - Window focus helper

// Makes the Settings window key the moment it appears and resets the activation
// policy back to .accessory (for dock-hidden mode) when the window closes.
private struct WindowFocuser: NSViewRepresentable {
    let showInDock: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            if !showInDock {
                NotificationCenter.default.addObserver(
                    forName: NSWindow.willCloseNotification,
                    object: window,
                    queue: .main
                ) { _ in
                    let otherVisible = NSApp.windows.contains { $0 !== window && $0.isVisible }
                    if !otherVisible { NSApp.setActivationPolicy(.accessory) }
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
                }

                SettingsSection(icon: "menubar.rectangle", title: "Menu Bar", color: .gray) {
                    SettingsRow(label: "Shows") {
                        Picker("", selection: $engine.menuBarMetric) {
                            ForEach(MetricsEngine.MenuBarMetric.allCases) { m in
                                Text(m.rawValue).tag(m)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: 140)
                    }
                    Divider().padding(.vertical, 4)
                    SettingsRow(label: "Style") {
                        Picker("", selection: $engine.menuBarStyle) {
                            ForEach(MetricsEngine.MenuBarStyle.allCases) { s in
                                Text(s.rawValue).tag(s)
                            }
                        }
                        .labelsHidden().pickerStyle(.menu).frame(maxWidth: 140)
                        .onChange(of: engine.menuBarStyle) { _, _ in engine.renderMenuBarImage() }
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
    }
}

// MARK: - Alerts tab

private struct AlertsTab: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(spacing: 16) {
            SettingsSection(icon: "bell.badge.fill", title: "Alerts", color: .orange) {
                SettingsRow(label: "Enable notifications") {
                    Toggle("", isOn: $engine.alertsEnabled).labelsHidden()
                }
                if engine.alertsEnabled {
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "cpu", label: "CPU above",
                        color: MetricTheme.cpu,
                        enabled: $engine.cpuAlertEnabled,
                        value: $engine.cpuAlertThreshold,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "memorychip", label: "Memory above",
                        color: MetricTheme.memory,
                        enabled: $engine.memoryAlertEnabled,
                        value: $engine.memoryAlertThresholdPercent,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "internaldrive", label: "Disk free below",
                        color: MetricTheme.disk,
                        enabled: $engine.diskAlertEnabled,
                        value: $engine.diskFreeAlertThresholdGB,
                        range: 1...50, step: 1, format: "%.0f GB"
                    )
                    Divider().padding(.vertical, 4)
                    AlertMetricRow(
                        icon: "cube.transparent", label: "GPU above",
                        color: .cyan,
                        enabled: $engine.gpuAlertEnabled,
                        value: $engine.gpuAlertThreshold,
                        range: 50...100, step: 5, format: "%.0f%%"
                    )
                    Divider().padding(.vertical, 4)
                    SettingsRow(label: "Thermal pressure") {
                        Toggle("", isOn: $engine.thermalAlertEnabled).labelsHidden()
                    }
                    Text("Thermal alerts fire on Serious or Critical. All alerts are rate-limited to once per 5 min.")
                        .font(.caption2).foregroundStyle(.secondary).padding(.top, 4)
                }
            }
        }
        .padding(16)
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
    }
}

private struct PanelGridPreview: View {
    @Binding var panelOrder: [MetricsEngine.Panel]
    @Binding var hiddenPanels: Set<MetricsEngine.Panel>

    private struct PreviewRow: Identifiable {
        var first: MetricsEngine.Panel?
        var second: MetricsEngine.Panel?
        var full: MetricsEngine.Panel?
        var id: String {
            [first?.id, second?.id, full?.id].compactMap { $0 }.joined(separator: "-")
        }
    }

    private var rows: [PreviewRow] {
        var result: [PreviewRow] = []
        var pending: MetricsEngine.Panel? = nil
        for panel in panelOrder {
            if panel.isFullWidth {
                if let p = pending { result.append(PreviewRow(first: p)); pending = nil }
                result.append(PreviewRow(full: panel))
            } else {
                if let p = pending {
                    result.append(PreviewRow(first: p, second: panel)); pending = nil
                } else {
                    pending = panel
                }
            }
        }
        if let p = pending { result.append(PreviewRow(first: p)) }
        return result
    }

    var body: some View {
        VStack(spacing: 6) {
            ForEach(rows) { row in
                if let full = row.full {
                    PanelMiniCard(panel: full, fullWidth: true,
                                  hidden: hiddenPanels.contains(full),
                                  panelOrder: $panelOrder, hiddenPanels: $hiddenPanels)
                        .frame(maxWidth: .infinity)
                } else {
                    HStack(spacing: 6) {
                        if let a = row.first {
                            PanelMiniCard(panel: a, fullWidth: false,
                                          hidden: hiddenPanels.contains(a),
                                          panelOrder: $panelOrder, hiddenPanels: $hiddenPanels)
                        }
                        if let b = row.second {
                            PanelMiniCard(panel: b, fullWidth: false,
                                          hidden: hiddenPanels.contains(b),
                                          panelOrder: $panelOrder, hiddenPanels: $hiddenPanels)
                        } else {
                            Color.clear.frame(height: 58)
                        }
                    }
                }
            }
        }
    }
}

private struct PanelMiniCard: View {
    let panel: MetricsEngine.Panel
    let fullWidth: Bool
    let hidden: Bool
    @Binding var panelOrder: [MetricsEngine.Panel]
    @Binding var hiddenPanels: Set<MetricsEngine.Panel>
    @State private var isTargeted = false

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 5) {
                Image(systemName: panelIcon(panel))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(hidden ? .secondary : panelColor(panel))
                Text(panel.rawValue)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(hidden ? .tertiary : .secondary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isTargeted ? panelColor(panel).opacity(0.25) :
                          hidden ? Color.primary.opacity(0.04) : panelColor(panel).opacity(0.1))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(isTargeted ? panelColor(panel) :
                                  panelColor(panel).opacity(hidden ? 0.1 : 0.3), lineWidth: 1)
            )
            .opacity(hidden ? 0.45 : 1)

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
        .dropDestination(for: MetricsEngine.Panel.self, action: { dropped, _ in
            guard let source = dropped.first, source != panel else { return false }
            guard let from = panelOrder.firstIndex(of: source),
                  let to   = panelOrder.firstIndex(of: panel) else { return false }
            var order = panelOrder
            order.move(fromOffsets: IndexSet(integer: from),
                       toOffset: to >= from ? to + 1 : to)
            panelOrder = order
            return true
        }, isTargeted: { isTargeted = $0 })
    }
}

private func panelIcon(_ panel: MetricsEngine.Panel) -> String {
    switch panel {
    case .cpu:       return MetricTheme.icon(for: .cpu)
    case .memory:    return MetricTheme.icon(for: .memory)
    case .disk:      return MetricTheme.icon(for: .disk)
    case .thermal:   return "thermometer.medium"
    case .gpu:       return "cube.transparent"
    case .battery:   return "battery.75percent"
    case .network:   return MetricTheme.icon(for: .network)
    case .bluetooth: return "dot.radiowaves.left.and.right"
    }
}

private func panelColor(_ panel: MetricsEngine.Panel) -> Color {
    switch panel {
    case .cpu:       return MetricTheme.cpu
    case .memory:    return MetricTheme.memory
    case .disk:      return MetricTheme.disk
    case .thermal:   return .orange
    case .gpu:       return .cyan
    case .battery:   return .green
    case .network:   return MetricTheme.networkDown
    case .bluetooth: return .blue
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
