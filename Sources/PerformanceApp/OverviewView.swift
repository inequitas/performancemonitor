import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

struct OverviewView: View {
    @ObservedObject var engine: MetricsEngine
    @Environment(\.openWindow) private var openWindow
    @Environment(\.openSettings) private var openSettings

    @AppStorage("card.cpuStyle")    private var cpuStyle:    CardChartStyle = .area
    @AppStorage("card.memoryStyle") private var memoryStyle: CardChartStyle = .area
    @AppStorage("card.diskStyle")   private var diskStyle:   CardChartStyle = .area

    private var visiblePanels: [MetricsEngine.Panel] {
        engine.settings.panelOrder.filter { !engine.settings.hiddenPanels.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(String(localized: "System Overview"))
                .font(.title3.weight(.semibold))
                .padding(.top, 12)
                .padding(.horizontal, 14)

            VStack(spacing: 10) {
                ForEach(MetricsEngine.panelLayout(visiblePanels)) { row in
                    if let full = row.full {
                        fullWidthCard(for: full)
                    } else {
                        HStack(spacing: 10) {
                            if let a = row.first { gridCard(for: a) }
                            if let b = row.second { gridCard(for: b) }
                            else { Color.clear }
                        }
                    }
                }
            }
            .padding(.horizontal, 14)

            Divider().padding(.horizontal, 14)

            HStack {
                Button {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                    // Activation policy resets to .accessory in SettingsView's
                    // WindowFocuser when the window actually closes, not on a timer.
                } label: {
                    Label(String(localized: "Settings"), systemImage: "gearshape")
                }
                .buttonStyle(.plain)
                Spacer()
                Button { NSApplication.shared.terminate(nil) } label: {
                    Label(String(localized: "Quit"), systemImage: "power")
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.bottom, 12)
        }
        .frame(width: 380)
        .background(.regularMaterial)
    }


    @ViewBuilder
    private func gridCard(for panel: MetricsEngine.Panel) -> some View {
        switch panel {
        case .cpu:
            OverviewCard(
                title: String(localized: "CPU"), icon: MetricsEngine.Panel.cpu.icon, color: MetricTheme.cpu,
                valueText: String(format: "%.0f%%", engine.cpuUsagePercent),
                history: engine.cpuHistory, unit: "%", fixedMax: 100,
                percentValue: engine.cpuUsagePercent,
                style: $cpuStyle, allowGauge: true
            ) { openDetail(.cpu) }
        case .memory:
            OverviewCard(
                title: String(localized: "Memory"), icon: MetricsEngine.Panel.memory.icon, color: MetricTheme.memory,
                valueText: String(format: "%.1f / %.0f GB", engine.memoryUsedGB, engine.memoryTotalGB),
                history: engine.memoryHistory, unit: "GB", fixedMax: max(engine.memoryTotalGB, 1),
                percentValue: engine.memoryTotalGB > 0 ? (engine.memoryUsedGB / engine.memoryTotalGB) * 100 : 0,
                style: $memoryStyle, allowGauge: true
            ) { openDetail(.memory) }
        case .disk:
            DiskCard(engine: engine, style: $diskStyle) { openDetail(.disk) }
        case .thermal:
            ThermalCard(state: engine.thermalState, cpuTemp: engine.cpuTemperatureC,
                        gpuTemp: engine.gpuTemperatureC, batteryTemp: engine.batteryTemperatureC
            ) { openDetail(.thermal) }
        case .gpu:
            GPUCard(name: engine.gpuName, usagePercent: engine.gpuUsagePercent,
                    history: engine.gpuHistory, displays: engine.displays) { openDetail(.gpu) }
        case .battery:
            if let percent = engine.batteryPercent {
                let watts = engine.batteryVoltage.flatMap { v in
                    engine.batteryAmperage.map { a in v * abs(Double(a)) / 1000 }
                }
                BatteryCard(percent: percent, isCharging: engine.batteryIsCharging,
                            powerSourceName: engine.powerSourceName,
                            timeRemainingMinutes: engine.batteryTimeRemainingMinutes,
                            watts: watts) { openDetail(.battery) }
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func fullWidthCard(for panel: MetricsEngine.Panel) -> some View {
        switch panel {
        case .network:
            NetworkOverviewCard(engine: engine) { openDetail(.network) }
        case .bluetooth:
            BluetoothOverviewCard(devices: engine.bluetoothDevices) { openDetail(.bluetooth) }
        default:
            EmptyView()
        }
    }

    private func openDetail(_ panel: MetricsEngine.Panel) {
        NSApp.activate(ignoringOtherApps: true)
        openWindow(id: "detail", value: panel)
    }
}

private func formatSpeedCompact(_ kbps: Double) -> String {
    kbps > 1024 ? String(format: "%.1fMB/s", kbps / 1024) : String(format: "%.0fKB/s", kbps)
}


// MARK: - Card chart style

enum CardChartStyle: String, CaseIterable, Identifiable {
    case area, gauge
    var id: String { rawValue }
    var label: String {
        switch self {
        case .area:  return String(localized: "Area")
        case .gauge: return String(localized: "Gauge")
        }
    }
    var systemImage: String {
        switch self {
        case .area:  return "chart.bar.fill"
        case .gauge: return "gauge.with.dots.needle.50percent"
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
            VStack(spacing: 6) {
                if style == .gauge, let percent = percentValue {
                    HStack {
                        Spacer()
                        RingGaugeView(value: percent, color: color)
                        Spacer()
                    }
                    .frame(height: 66)
                } else {
                    Text(valueText)
                        .font(.system(.body, design: .rounded))
                        .fontWeight(.semibold)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                        .frame(maxWidth: .infinity, alignment: .center)
                    MetricChart(values: history, unit: unit, fixedMax: fixedMax, showAxes: false, color: color, style: .area, accessibilityDescription: String(format: String(localized: "%@ history"), title), valueFormatter: valueFormatter)
                        .frame(height: 46)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(color.opacity(0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - Thermal card

private struct ThermalCard: View {
    let state: ProcessInfo.ThermalState
    let cpuTemp: Double?
    let gpuTemp: Double?
    let batteryTemp: Double?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    cardIcon("thermometer.medium", color: state.color)
                    Text(String(localized: "Thermal")).font(.caption).foregroundStyle(.secondary)
                }
                VStack(alignment: .center, spacing: 4) {
                    if let t = cpuTemp {
                        tempRow("cpu", String(localized: "CPU"), t)
                    }
                    if let t = gpuTemp {
                        tempRow("cube.transparent", String(localized: "GPU"), t)
                    }
                    if let t = batteryTemp {
                        tempRow("battery.75percent", String(localized: "Bat"), t)
                    }
                    HStack(spacing: 4) {
                        Circle().fill(state.color).frame(width: 7, height: 7).accessibilityHidden(true)
                        Text(state.label).font(.caption2).foregroundStyle(.secondary)
                    }
                    .padding(.top, 1)
                }
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .padding(10)
            .frame(maxWidth: .infinity, minHeight: cardHeight, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(state.color.opacity(0.15), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func tempColor(_ celsius: Double) -> Color {
        switch celsius {
        case ..<60:  return .green
        case ..<80:  return .yellow
        case ..<95:  return .orange
        default:     return .red
        }
    }

    // Mirrors tempColor's thresholds in words, so the severity conveyed by
    // colour alone is also available to VoiceOver / colour-blind users.
    private func tempSeverityWord(_ celsius: Double) -> String {
        switch celsius {
        case ..<60:  return String(localized: "normal")
        case ..<80:  return String(localized: "warm")
        case ..<95:  return String(localized: "hot")
        default:     return String(localized: "critical")
        }
    }

    private func tempRow(_ icon: String, _ label: String, _ celsius: Double) -> some View {
        let color = tempColor(celsius)
        return HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(color)
                .frame(width: 14)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 22, alignment: .leading)
            Text(String(format: "%.0f°C", celsius))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(color)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(String(format: String(localized: "%ld°C, %@"), Int(celsius.rounded()), tempSeverityWord(celsius)))
    }
}

// MARK: - Disk card

private struct DiskCard: View {
    @ObservedObject var engine: MetricsEngine
    @Binding var style: CardChartStyle
    let action: () -> Void

    private let readColor  = Color.indigo
    private let writeColor = Color.purple

    private var usedPercent: Double {
        engine.diskTotalGB > 0 ? ((engine.diskTotalGB - engine.diskFreeGB) / engine.diskTotalGB) * 100 : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                cardIcon(MetricsEngine.Panel.disk.icon, color: readColor)
                Text(String(localized: "Disk")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(CardChartStyle.allCases) { s in
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
            VStack(alignment: .leading, spacing: 6) {
                if style == .gauge {
                    HStack(spacing: 0) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(String(format: "%.0f GB", engine.diskFreeGB))
                                .font(.system(.body, design: .rounded)).fontWeight(.semibold)
                            Text(String(format: String(localized: "free of %ld GB"), Int(engine.diskTotalGB)))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        Spacer()
                        RingGaugeView(value: usedPercent, color: readColor)
                    }
                    .frame(maxHeight: .infinity)
                } else {
                    HStack(spacing: 10) {
                        speedLabel("R", engine.diskReadKBps,  readColor)
                        speedLabel("W", engine.diskWriteKBps, writeColor)
                    }
                    DiskButterflyChart(
                        readHistory:  engine.diskReadHistory,
                        writeHistory: engine.diskWriteHistory,
                        readColor:    readColor,
                        writeColor:   writeColor
                    )
                    .frame(height: 46)
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(readColor.opacity(0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

    private func speedLabel(_ label: String, _ kbps: Double, _ color: Color) -> some View {
        HStack(spacing: 3) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(formatSpeedCompact(kbps)).font(.caption2.monospacedDigit()).foregroundStyle(color)
        }
    }
}

private struct DiskButterflyChart: View {
    let readHistory:  [Double]
    let writeHistory: [Double]
    let readColor:    Color
    let writeColor:   Color

    private var sharedMax: Double { absoluteMax(readHistory, writeHistory) }

    var body: some View {
        VStack(spacing: 0) {
            MetricChart(values: readHistory, fixedMax: sharedMax, showAxes: false, fillFrame: true, color: readColor, style: .area, accessibilityDescription: String(localized: "Disk read speed history"), valueFormatter: formatSpeedCompact)
            Color.primary.opacity(0.25).frame(height: 1)
            MetricChart(values: writeHistory, fixedMax: sharedMax, showAxes: false, fillFrame: true, color: writeColor, style: .area, accessibilityDescription: String(localized: "Disk write speed history"), valueFormatter: formatSpeedCompact)
                .scaleEffect(y: -1)
        }
    }
}

// MARK: - Battery card

private struct BatteryCard: View {
    let percent: Int
    let isCharging: Bool
    let powerSourceName: String
    let timeRemainingMinutes: Int?
    let watts: Double?
    let action: () -> Void

    private var color: Color {
        if isCharging { return .green }
        if percent < 20 { return .red }
        if percent < 50 { return .orange }
        return .green
    }

    // Only the number's colour flags a low battery today — say it in words too.
    private var batteryAccessibilityValue: String {
        guard !isCharging else { return String(format: String(localized: "%ld percent, charging"), percent) }
        if percent < 20 { return String(format: String(localized: "%ld percent, low battery"), percent) }
        return String(format: String(localized: "%ld percent"), percent)
    }

    // Time + wattage detail; nil when there's nothing meaningful to show
    private var detailText: String? {
        if isCharging {
            // macOS reports 0 min when nearly full — skip the time in that case
            let wattStr = watts.map { String(format: String(localized: "%.0fW charging"), $0) }
            if let m = timeRemainingMinutes, m > 5 {
                let h = m / 60, mins = m % 60
                let timeStr = h > 0
                    ? String(format: String(localized: "%ldh %ldm to full"), h, mins)
                    : String(format: String(localized: "%ldm to full"), mins)
                return [timeStr, wattStr].compactMap { $0 }.joined(separator: " · ")
            }
            return wattStr
        } else {
            // On battery — time remaining is what matters; skip the draw wattage
            guard let m = timeRemainingMinutes else { return nil }
            let h = m / 60, mins = m % 60
            return h > 0
                ? String(format: String(localized: "%ldh %ldm remaining"), h, mins)
                : String(format: String(localized: "%ldm remaining"), mins)
        }
    }

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    cardIcon(isCharging ? "battery.100percent.bolt" : "battery.75percent", color: color)
                    Text(String(localized: "Battery")).font(.caption).foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    Text(String(format: "%ld%%", percent))
                        .font(.system(.body, design: .rounded)).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .accessibilityValue(batteryAccessibilityValue)
                    Text(isCharging ? String(localized: "Charging") : String(localized: "On Battery"))
                        .font(.caption2).fontWeight(.medium)
                        .foregroundStyle(isCharging ? .green : .secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if let detail = detailText {
                        Text(detail)
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                }
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

private enum GPUCardStyle: String, CaseIterable, Identifiable {
    case area, gauge, info
    var id: String { rawValue }
    var label: String {
        switch self {
        case .area:  return String(localized: "Chart")
        case .gauge: return String(localized: "Gauge")
        case .info:  return String(localized: "Info")
        }
    }
    var systemImage: String {
        switch self {
        case .area:  return "chart.bar.fill"
        case .gauge: return "gauge.with.dots.needle.50percent"
        case .info:  return "info.circle"
        }
    }
}

private struct GPUCard: View {
    let name: String
    let usagePercent: Double
    let history: [Double]
    let displays: [DisplayInfo]
    let action: () -> Void

    @State private var style: GPUCardStyle = .area

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                cardIcon("cube.transparent", color: .cyan)
                Text(String(localized: "GPU & Displays")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Menu {
                    ForEach(GPUCardStyle.allCases) { s in
                        Button { style = s } label: { Label(s.label, systemImage: s.systemImage) }
                    }
                } label: {
                    Image(systemName: style.systemImage).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 16)
            }
            VStack(spacing: 4) {
                switch style {
                case .area:
                    Text(String(format: "%.0f%%", usagePercent))
                        .font(.system(.body, design: .rounded)).fontWeight(.semibold)
                        .frame(maxWidth: .infinity, alignment: .center)
                    MetricChart(values: history, unit: "%", fixedMax: 100,
                                showAxes: false, color: .cyan, style: .area,
                                accessibilityDescription: String(localized: "GPU usage history")) { String(format: "%.0f%%", $0) }
                        .frame(height: 46)
                case .gauge:
                    HStack {
                        Spacer()
                        RingGaugeView(value: usagePercent, color: .cyan)
                        Spacer()
                    }
                    .frame(height: 66)
                case .info:
                    Text(name)
                        .font(.system(.callout, design: .rounded)).fontWeight(.semibold)
                        .lineLimit(1).minimumScaleFactor(0.7)
                        .frame(maxWidth: .infinity, alignment: .center)
                    if displays.isEmpty {
                        Text(String(localized: "No display info"))
                            .font(.caption2).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .center)
                    } else {
                        ForEach(displays) { d in
                            HStack(spacing: 4) {
                                Image(systemName: d.isMain ? "display" : "display.2")
                                    .font(.caption2).foregroundStyle(.cyan)
                                Text(d.name)
                                    .font(.caption2).lineLimit(1).foregroundStyle(.secondary)
                                if d.isMain {
                                    Text(String(localized: "main")).font(.caption2).foregroundStyle(.cyan.opacity(0.7))
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: cardHeight, maxHeight: cardHeight, alignment: .topLeading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.cyan.opacity(0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - Network overview (full width, with IPs)

private struct NetworkOverviewCard: View {
    @ObservedObject var engine: MetricsEngine
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                cardIcon(MetricsEngine.Panel.network.icon, color: MetricTheme.networkDown)
                Text(String(localized: "Network")).font(.caption).foregroundStyle(.secondary)
                Image(systemName: engine.isVPNActive ? "lock.shield.fill" : "lock.shield")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(engine.isVPNActive
                        ? (engine.vpnIsFortiClient ? Color.blue : Color.green)
                        : Color.secondary)
                    .accessibilityLabel(engine.isVPNActive
                        ? (engine.vpnIsFortiClient ? String(localized: "VPN active, FortiClient") : String(localized: "VPN active"))
                        : String(localized: "VPN inactive"))
                Spacer()
                HStack(spacing: 5) {
                    let visibleIfaces = engine.localInterfaces.filter { $0.kind != .vpn }
                    if visibleIfaces.isEmpty && engine.isConnected {
                        Image(systemName: "network")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.green)
                            .accessibilityLabel(String(localized: "Connected"))
                    } else {
                        ForEach(visibleIfaces) { iface in
                            let isHotspot = iface.kind == .wifi && engine.isLikelyHotspot
                            let ifaceLabel = isHotspot ? String(localized: "Personal Hotspot") : iface.displayName
                            Image(systemName: isHotspot ? "personalhotspot" : iface.icon)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(iface.isPrimary ? Color.green : Color.primary)
                                .accessibilityLabel(iface.isPrimary
                                    ? String(format: String(localized: "%@, primary connection"), ifaceLabel)
                                    : ifaceLabel)
                        }
                    }
                }
                HStack(spacing: 10) {
                    Label(formatSpeedCompact(engine.downloadSpeedKBps), systemImage: "arrow.down")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MetricTheme.networkDown)
                    Label(formatSpeedCompact(engine.uploadSpeedKBps), systemImage: "arrow.up")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(MetricTheme.networkUp)
                }
                Circle()
                    .fill(engine.isConnected ? Color.green : Color.red)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel(engine.isConnected ? String(localized: "Connected") : String(localized: "Disconnected"))
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }

            Divider()

            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    if engine.localInterfaces.isEmpty {
                        CopyableIPRow(icon: "network", label: String(localized: "Local IP"), value: "—")
                    } else {
                        ForEach(engine.localInterfaces) { iface in
                            CopyableIPRow(icon: iface.icon, label: iface.displayName, value: iface.address,
                                          iconColor: iface.isPrimary ? .green : .secondary)
                        }
                    }
                    CopyableIPRow(icon: "globe", label: String(localized: "Public IP"), value: engine.publicIP ?? String(localized: "Looking up…"))
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
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }
}

// MARK: - Bluetooth overview (full width, connected rows)

struct BluetoothOverviewCard: View {
    let devices: [BluetoothDevice]
    let action: () -> Void

    private var connected: [BluetoothDevice] { devices.filter { $0.isConnected } }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                cardIcon("dot.radiowaves.left.and.right", color: .blue)
                Text(String(localized: "Bluetooth")).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(String(format: String(localized: "%ld connected"), connected.count)).font(.caption2).foregroundStyle(.secondary)
                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
            }

            if connected.isEmpty {
                Text(String(localized: "No devices connected")).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(connected) { device in
                    HStack(spacing: 8) {
                        Image(systemName: device.icon).font(.system(size: 12)).foregroundStyle(.blue).frame(width: 16)
                        Text(device.name).font(.caption).lineLimit(1)
                        Spacer()
                        if device.batteryLeft != nil || device.batteryRight != nil || device.batteryCase != nil {
                            HStack(spacing: 4) {
                                if let l = device.batteryLeft  { EarbudBatteryPill("L", l) }
                                if let r = device.batteryRight { EarbudBatteryPill("R", r) }
                                if let c = device.batteryCase  { EarbudBatteryPill(String(localized: "Case"), c) }
                            }
                        } else if let pct = device.batteryPercent {
                            HStack(spacing: 3) {
                                Image(systemName: batterySystemImage(pct)).font(.caption2).foregroundStyle(pct < 20 ? .red : pct < 40 ? .orange : .green)
                                Text(String(format: "%ld%%", pct)).font(.caption.monospacedDigit()).foregroundStyle(pct < 20 ? .red : .secondary)
                            }
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(String(localized: "Battery"))
                            .accessibilityValue(pct < 20 ? String(format: String(localized: "%ld percent, low"), pct) : String(format: String(localized: "%ld percent"), pct))
                        }
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color.blue.opacity(0.15), lineWidth: 1))
        .contentShape(Rectangle())
        .onTapGesture(perform: action)
    }

}

// MARK: - Ring gauge

struct RingGaugeView: View {
    let value: Double   // 0–100
    let color: Color

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.15), lineWidth: 8)
            Circle()
                .trim(from: 0, to: CGFloat(min(max(value / 100.0, 0), 1)))
                .stroke(color, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.4), value: value)
            Text(String(format: "%.0f%%", value))
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(color)
        }
        .frame(width: 60, height: 60)
    }
}

// MARK: - Shared icon helper

private func cardIcon(_ name: String, color: Color) -> some View {
    ZStack {
        RoundedRectangle(cornerRadius: 7).fill(color.opacity(0.18)).frame(width: 22, height: 22)
        Image(systemName: name).font(.system(size: 11, weight: .semibold)).foregroundStyle(color)
    }
}
