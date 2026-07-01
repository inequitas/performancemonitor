import SwiftUI
import AppKit

struct OverviewView: View {
    @ObservedObject var engine: MetricsEngine
    @Environment(\.openWindow) private var openWindow

    @State private var cpuStyle: CardChartStyle = .area
    @State private var memoryStyle: CardChartStyle = .area
    @State private var diskStyle: CardChartStyle = .area

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("System Overview")
                .font(.title3.weight(.semibold))
                .padding(.top, 12)
                .padding(.horizontal, 14)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                OverviewCard(
                    title: "CPU",
                    icon: MetricTheme.icon(for: .cpu),
                    color: MetricTheme.cpu,
                    valueText: String(format: "%.0f%%", engine.cpuUsagePercent),
                    history: engine.cpuHistory,
                    unit: "%",
                    fixedMax: 100,
                    percentValue: engine.cpuUsagePercent,
                    style: $cpuStyle,
                    allowGauge: true
                ) { openDetail(.cpu) }

                OverviewCard(
                    title: "Memory",
                    icon: MetricTheme.icon(for: .memory),
                    color: MetricTheme.memory,
                    valueText: String(format: "%.1f / %.0f GB", engine.memoryUsedGB, engine.memoryTotalGB),
                    history: engine.memoryHistory,
                    unit: "GB",
                    fixedMax: max(engine.memoryTotalGB, 1),
                    percentValue: engine.memoryTotalGB > 0 ? (engine.memoryUsedGB / engine.memoryTotalGB) * 100 : 0,
                    style: $memoryStyle,
                    allowGauge: true
                ) { openDetail(.memory) }

                OverviewCard(
                    title: "Disk",
                    icon: MetricTheme.icon(for: .disk),
                    color: MetricTheme.disk,
                    valueText: String(format: "%.0f GB free", engine.diskFreeGB),
                    history: engine.diskReadHistory,
                    unit: "KB/s",
                    fixedMax: nil,
                    percentValue: engine.diskTotalGB > 0 ? ((engine.diskTotalGB - engine.diskFreeGB) / engine.diskTotalGB) * 100 : 0,
                    style: $diskStyle,
                    allowGauge: true,
                    valueFormatter: formatSpeed
                ) { openDetail(.disk) }

                ThermalCard(state: engine.thermalState) { openDetail(.cpu) }

                GPUCard(name: engine.gpuName, displays: engine.displays) { openDetail(.gpu) }

                if let percent = engine.batteryPercent {
                    BatteryCard(
                        percent: percent,
                        isCharging: engine.batteryIsCharging,
                        powerSourceName: engine.powerSourceName,
                        timeRemainingMinutes: engine.batteryTimeRemainingMinutes
                    ) { openDetail(.battery) }
                }
            }
            .padding(.horizontal, 14)

            // Network — full-width with IP copy rows
            NetworkOverviewCard(engine: engine) { openDetail(.network) }
                .padding(.horizontal, 14)

            // Bluetooth — full-width with connected device rows
            BluetoothOverviewCard(
                devices: engine.bluetoothDevices,
                action: { openDetail(.bluetooth) }
            )
            .padding(.horizontal, 14)

            Divider().padding(.horizontal, 14)

            HStack {
                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label("Quit", systemImage: "power")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 380)
        .background(.regularMaterial)
    }

    private func openDetail(_ kind: DetailWindow.Kind) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "detail", value: kind)
    }

    private func formatSpeed(_ kbps: Double) -> String {
        if kbps > 1024 { return String(format: "%.1fMB/s", kbps / 1024) }
        return String(format: "%.0fKB/s", kbps)
    }
}

// MARK: - Card chart style

enum CardChartStyle: String, CaseIterable, Identifiable {
    case line, area, bar, gauge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .line: return "Line"
        case .area: return "Area"
        case .bar: return "Bar"
        case .gauge: return "Gauge"
        }
    }
    var systemImage: String {
        switch self {
        case .line: return "chart.xyaxis.line"
        case .area: return "chart.bar.fill"
        case .bar: return "chart.bar"
        case .gauge: return "gauge.with.dots.needle.50percent"
        }
    }
    var asChartDisplayStyle: ChartDisplayStyle {
        switch self {
        case .line: return .line
        case .area: return .area
        case .bar: return .bar
        case .gauge: return .area
        }
    }
}

// Fixed height shared by every grid card so all rows look uniform.
private let cardHeight: CGFloat = 120

// MARK: - Generic overview card

private struct OverviewCard: View {
    let title: String
    let icon: String
    let color: Color
    let valueText: String
    let history: [Double]
    let unit: String
    let fixedMax: Double?
    let percentValue: Double?
    @Binding var style: CardChartStyle
    let allowGauge: Bool
    var valueFormatter: (Double) -> String = { String(format: "%.1f", $0) }
    let action: () -> Void

    private var availableStyles: [CardChartStyle] {
        allowGauge ? CardChartStyle.allCases : CardChartStyle.allCases.filter { $0 != .gauge }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                cardIcon(icon, color: color)
                Text(title).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(availableStyles) { s in
                        Button { style = s } label: {
                            Label(s.label, systemImage: s.systemImage)
                        }
                    }
                } label: {
                    Image(systemName: style.systemImage).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
            }
            Button(action: action) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(valueText)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    if style == .gauge, let percent = percentValue {
                        HStack {
                            Spacer()
                            Gauge(value: min(max(percent, 0), 100), in: 0...100) {} currentValueLabel: {
                                Text(String(format: "%.0f", percent)).font(.caption2)
                            }
                            .gaugeStyle(.accessoryCircularCapacity)
                            .tint(color)
                            Spacer()
                        }
                        .frame(height: 46)
                    } else {
                        MetricChart(values: history, unit: unit, fixedMax: fixedMax, showAxes: false, color: color, style: style.asChartDisplayStyle, valueFormatter: valueFormatter)
                            .frame(height: 46)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Thermal card

private struct ThermalCard: View {
    let state: ProcessInfo.ThermalState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    cardIcon("thermometer.medium", color: state.color)
                    Text("Thermal").font(.caption).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Circle().fill(state.color).frame(width: 9, height: 9)
                    Text(state.label).font(.system(.body, design: .rounded)).fontWeight(.semibold)
                }
                .frame(height: 46, alignment: .center)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(state.color.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Battery card

private struct BatteryCard: View {
    let percent: Int
    let isCharging: Bool
    let powerSourceName: String
    let timeRemainingMinutes: Int?
    let action: () -> Void

    private var color: Color {
        if isCharging { return .green }
        if percent < 20 { return .red }
        if percent < 50 { return .orange }
        return .green
    }

    private var timeText: String {
        guard let minutes = timeRemainingMinutes else { return powerSourceName }
        let h = minutes / 60, m = minutes % 60
        return isCharging ? "\(h)h \(m)m to full" : "\(h)h \(m)m left"
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    cardIcon(isCharging ? "battery.100percent.bolt" : "battery.75percent", color: color)
                    Text("Battery").font(.caption).foregroundStyle(.secondary)
                }
                Text("\(percent)%").font(.system(.body, design: .rounded)).fontWeight(.semibold)
                Text(timeText).font(.caption2).foregroundStyle(.secondary).frame(height: 46 - 16, alignment: .top)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GPU card

private struct GPUCard: View {
    let name: String
    let displays: [DisplayInfo]
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    cardIcon("cube.transparent", color: .cyan)
                    Text("GPU & Displays").font(.caption).foregroundStyle(.secondary)
                }
                Text(name)
                    .font(.system(.callout, design: .rounded)).fontWeight(.semibold)
                    .lineLimit(1).minimumScaleFactor(0.7)
                if displays.isEmpty {
                    Text("No display info")
                        .font(.caption2).foregroundStyle(.secondary)
                } else {
                    ForEach(displays) { d in
                        HStack(spacing: 4) {
                            Image(systemName: d.isMain ? "display" : "display.2")
                                .font(.caption2).foregroundStyle(.cyan)
                            Text(d.name)
                                .font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                            if d.isMain {
                                Text("main")
                                    .font(.caption2)
                                    .foregroundStyle(.cyan.opacity(0.7))
                            }
                        }
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.cyan.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Network overview (full width, with IPs)

private struct NetworkOverviewCard: View {
    @ObservedObject var engine: MetricsEngine
    let action: () -> Void

    private func formatSpeed(_ kbps: Double) -> String {
        kbps > 1024 ? String(format: "%.1fMB/s", kbps / 1024) : String(format: "%.0fKB/s", kbps)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack(spacing: 6) {
                    cardIcon(MetricTheme.icon(for: .network), color: MetricTheme.networkDown)
                    Text("Network").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    HStack(spacing: 10) {
                        Label(formatSpeed(engine.downloadSpeedKBps), systemImage: "arrow.down")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MetricTheme.networkDown)
                        Label(formatSpeed(engine.uploadSpeedKBps), systemImage: "arrow.up")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(MetricTheme.networkUp)
                    }
                    HStack(spacing: 4) {
                        Circle()
                            .fill(engine.isConnected ? Color.green : Color.red)
                            .frame(width: 7, height: 7)
                        if engine.isVPNActive {
                            Image(systemName: "lock.shield.fill").font(.caption2).foregroundStyle(.green)
                        }
                    }
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            Divider()

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if let primary = engine.localInterfaces.first {
                        CopyableIPRow(label: primary.name, value: primary.address)
                    } else {
                        CopyableIPRow(label: "Local IP", value: "—")
                    }
                    CopyableIPRow(label: "Public IP", value: engine.publicIP ?? "Looking up…")
                }
                if let rssi = engine.wifiRSSI {
                    Spacer()
                    WiFiSignalBars(rssi: rssi)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(MetricTheme.networkDown.opacity(0.15), lineWidth: 1))
    }
}

// MARK: - Bluetooth overview (full width, connected rows)

struct BluetoothOverviewCard: View {
    let devices: [BluetoothDevice]
    let action: () -> Void

    private var connected: [BluetoothDevice] { devices.filter { $0.isConnected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: action) {
                HStack(spacing: 6) {
                    cardIcon("dot.radiowaves.left.and.right", color: .blue)
                    Text("Bluetooth").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(connected.count) connected").font(.caption2).foregroundStyle(.secondary)
                    Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                }
            }
            .buttonStyle(.plain)

            if connected.isEmpty {
                Text("No devices connected").font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(connected) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.icon).font(.system(size: 12)).foregroundStyle(.blue).frame(width: 16)
                        Text(device.name).font(.caption).lineLimit(1)
                        Spacer()
                        if let pct = device.batteryPercent {
                            HStack(spacing: 3) {
                                Image(systemName: batteryIcon(pct)).font(.caption2).foregroundStyle(pct < 20 ? .red : pct < 40 ? .orange : .green)
                                Text("\(pct)%").font(.caption.monospacedDigit()).foregroundStyle(pct < 20 ? .red : .secondary)
                            }
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.blue.opacity(0.15), lineWidth: 1))
    }

    private func batteryIcon(_ pct: Int) -> String {
        switch pct {
        case 0..<20: return "battery.0percent"
        case 20..<40: return "battery.25percent"
        case 40..<65: return "battery.50percent"
        case 65..<90: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

// MARK: - Shared icon helper

private func cardIcon(_ name: String, color: Color) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.18)).frame(width: 22, height: 22)
        Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
    }
}
