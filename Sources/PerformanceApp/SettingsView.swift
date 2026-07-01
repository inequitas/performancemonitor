import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var launchAtLogin: Bool = SMAppService.mainApp.status == .enabled

    var body: some View {
        ScrollView {
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
                    SettingsRow(label: "Menu bar shows") {
                        Picker("", selection: $engine.menuBarMetric) {
                            ForEach(MetricsEngine.MenuBarMetric.allCases) { m in
                                Text(m.label).tag(m)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                        .frame(maxWidth: 140)
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

                SettingsSection(icon: "list.number", title: "Processes", color: .blue) {
                    SettingsRow(label: "Top processes shown") {
                        HStack(spacing: 12) {
                            Button {
                                if engine.topProcessCount > 3 { engine.topProcessCount -= 1 }
                            } label: {
                                Image(systemName: "minus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(engine.topProcessCount > 3 ? Color.secondary : Color.secondary.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                            Text("\(engine.topProcessCount)")
                                .font(.system(.body, design: .rounded).weight(.semibold))
                                .frame(width: 24)
                                .multilineTextAlignment(.center)
                            Button {
                                if engine.topProcessCount < 15 { engine.topProcessCount += 1 }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                    .foregroundStyle(engine.topProcessCount < 15 ? Color.blue : Color.secondary.opacity(0.3))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

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
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }

                SettingsSection(icon: "bell.badge.fill", title: "Alerts", color: .orange) {
                    SettingsRow(label: "Enable notifications") {
                        Toggle("", isOn: $engine.alertsEnabled).labelsHidden()
                    }
                    if engine.alertsEnabled {
                        Divider().padding(.vertical, 4)
                        SettingsRow(label: "CPU alert above") {
                            HStack(spacing: 8) {
                                Slider(value: $engine.cpuAlertThreshold, in: 50...100, step: 5)
                                Text(String(format: "%.0f%%", engine.cpuAlertThreshold))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36)
                            }
                        }
                        Divider().padding(.vertical, 4)
                        SettingsRow(label: "Disk free below") {
                            HStack(spacing: 8) {
                                Slider(value: $engine.diskFreeAlertThresholdGB, in: 1...50, step: 1)
                                Text(String(format: "%.0f GB", engine.diskFreeAlertThresholdGB))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                    .frame(width: 36)
                            }
                        }
                        Text("Thermal alerts fire on Serious or Critical pressure. All alerts are rate-limited to once every 5 min per type.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                }

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
        .frame(width: 420)
        .frame(minHeight: 380, maxHeight: 640)
        .background(.regularMaterial)
        .navigationTitle("Settings")
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
                Text(title)
                    .font(.headline)
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
