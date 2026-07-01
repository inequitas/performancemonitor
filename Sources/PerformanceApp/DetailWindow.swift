import SwiftUI
import AppKit

struct DetailWindow: View {
    enum Kind: String, Codable, Hashable, CaseIterable, Identifiable {
        case cpu, memory, network, disk, gpu, battery, bluetooth
        var id: String { rawValue }
        var title: String {
            switch self {
            case .cpu: return "CPU"
            case .memory: return "Memory"
            case .network: return "Network"
            case .disk: return "Disk"
            case .gpu: return "GPU & Displays"
            case .battery: return "Battery"
            case .bluetooth: return "Bluetooth"
            }
        }
    }

    let kind: Kind
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        ScrollView {
            Group {
                switch kind {
                case .cpu: CPUDetailView(engine: engine)
                case .memory: MemoryDetailView(engine: engine)
                case .network: NetworkDetailView(engine: engine)
                case .disk: DiskDetailView(engine: engine)
                case .gpu: GPUDetailView(engine: engine)
                case .battery: BatteryDetailView(engine: engine)
                case .bluetooth: BluetoothDetailView(engine: engine)
                }
            }
            .padding()
            .frame(width: 420, alignment: .leading)
        }
        .frame(width: 420, height: 540)
        .navigationTitle(kind.title)
        .background(.regularMaterial)
        .background(WindowFloatAccessor())
    }
}

// MARK: - Shared components

private struct ChartStylePicker: View {
    @Binding var style: ChartDisplayStyle
    var body: some View {
        Picker("", selection: $style) {
            ForEach(ChartDisplayStyle.allCases) { s in
                Image(systemName: s.systemImage).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 110)
    }
}

private struct SectionCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct InfoButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(width: 280)
        }
    }
}

// MARK: - Process list

private struct ProcessListView: View {
    let title: String
    let icon: String
    let color: Color
    let processes: [ProcessUsage]
    let unit: String
    let engine: MetricsEngine

    @State private var pendingKill: ProcessUsage?
    @State private var paused = false
    @State private var frozenList: [ProcessUsage] = []

    private var displayed: [ProcessUsage] { paused ? frozenList : processes }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Button {
                    if !paused { frozenList = Array(processes.prefix(engine.topProcessCount)) }
                    paused.toggle()
                } label: {
                    Image(systemName: paused ? "play.circle.fill" : "pause.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(paused ? color : .secondary)
                }
                .buttonStyle(.plain)
                .help(paused ? "Resume live updates" : "Pause list")
            }

            if displayed.isEmpty {
                Text(paused ? "No data captured." : "Loading…")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(displayed.prefix(engine.topProcessCount)) { proc in
                    HStack(spacing: 6) {
                        Text(proc.name)
                            .font(.caption)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1f%@", proc.value, unit))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if proc.pid > 0 {
                            Button { pendingKill = proc } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help("Quit \(proc.name)")
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        if proc.pid > 0 {
                            Button("Quit \(proc.name)", role: .destructive) { pendingKill = proc }
                        }
                    }
                }
            }
        }
        .alert("Quit \(pendingKill?.name ?? "")?", isPresented: Binding(
            get: { pendingKill != nil },
            set: { if !$0 { pendingKill = nil } }
        )) {
            Button("Cancel", role: .cancel) { pendingKill = nil }
            Button("Quit", role: .destructive) {
                if let proc = pendingKill { engine.terminateProcess(pid: proc.pid) }
                pendingKill = nil
            }
        } message: {
            Text("This sends a quit signal to the process (PID \(pendingKill?.pid ?? 0)). Unsaved work may be lost.")
        }
    }
}

// MARK: - CPU

struct CPUDetailView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var style: ChartDisplayStyle = .area

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("CPU", systemImage: MetricTheme.icon(for: .cpu))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MetricTheme.cpu)
                Spacer()
                ChartStylePicker(style: $style)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "%.1f%%", engine.cpuUsagePercent))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MetricTheme.cpu)
                    MetricChart(values: engine.cpuHistory, unit: "%", fixedMax: 100, color: MetricTheme.cpu, style: style) { String(format: "%.0f%%", $0) }
                        .frame(height: 110)
                    HStack(spacing: 16) {
                        Label(String(format: "User %.0f%%", engine.cpuUserPercent), systemImage: "person.fill")
                        Label(String(format: "Sys %.0f%%", engine.cpuSystemPercent), systemImage: "gearshape.fill")
                        Label(String(format: "Idle %.0f%%", engine.cpuIdlePercent), systemImage: "moon.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(String(format: "Load avg: %.2f  %.2f  %.2f  (1 / 5 / 15 min)", engine.loadAverages.one, engine.loadAverages.five, engine.loadAverages.fifteen))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Per-core").font(.subheadline.weight(.semibold))
                        Spacer()
                        if engine.performanceCoreCount > 0 {
                            Text("P:\(engine.performanceCoreCount)  E:\(engine.efficiencyCoreCount)")
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        InfoButton(text: "P = Performance cores (faster, higher power). E = Efficiency cores (slower, lower power). macOS assigns which core handles each workload automatically. On Intel Macs all cores are equivalent and show as Core N.")
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(engine.perCoreUsage.enumerated()), id: \.offset) { idx, usage in
                                HStack {
                                    let label: String = {
                                        guard engine.performanceCoreCount > 0 else { return "Core \(idx)" }
                                        return idx < engine.performanceCoreCount ? "P\(idx)" : "E\(idx - engine.performanceCoreCount)"
                                    }()
                                    Text(label).frame(width: 40, alignment: .leading).font(.caption)
                                    ProgressView(value: usage, total: 100)
                                        .tint(idx < engine.performanceCoreCount ? MetricTheme.cpu : MetricTheme.cpu.opacity(0.55))
                                    Text(String(format: "%.0f%%", usage)).frame(width: 36).font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Thermal Pressure", systemImage: "thermometer.medium")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(engine.thermalState.color)
                        Spacer()
                        InfoButton(text: "This is the macOS thermal throttling signal — not an exact temperature reading.\n\n• Nominal: No throttling. System running normally.\n• Fair: Slight throttling may be occurring.\n• Serious: Active throttling. Performance is being reduced to cool the system.\n• Critical: Severe throttling. Immediate action recommended (close apps, remove from enclosed spaces).\n\nExact die temperatures (CPU/GPU) are not readable on Apple Silicon without a privileged kernel extension. macOS blocks SMC access for user-space apps.")
                    }
                    HStack(spacing: 8) {
                        Circle().fill(engine.thermalState.color).frame(width: 10, height: 10)
                        Text(engine.thermalState.label)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
            }

            SectionCard {
                ProcessListView(title: "Top CPU", icon: "cpu", color: MetricTheme.cpu, processes: engine.topCPUProcesses, unit: "%", engine: engine)
            }
            Spacer()
        }
    }
}

// MARK: - Memory

struct MemoryDetailView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var style: ChartDisplayStyle = .area

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Memory", systemImage: MetricTheme.icon(for: .memory))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MetricTheme.memory)
                Spacer()
                ChartStylePicker(style: $style)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(String(format: "%.2f", engine.memoryUsedGB)) GB / \(String(format: "%.2f", engine.memoryTotalGB)) GB")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(MetricTheme.memory)
                    MetricChart(values: engine.memoryHistory, unit: "GB", fixedMax: max(engine.memoryTotalGB, 1), color: MetricTheme.memory, style: style) { String(format: "%.1f GB", $0) }
                        .frame(height: 110)
                    HStack(spacing: 4) {
                        HStack(spacing: 16) {
                            Label(String(format: "App %.1fGB", engine.memoryAppGB), systemImage: "app.fill")
                            Label(String(format: "Wired %.1fGB", engine.memoryWiredGB), systemImage: "lock.fill")
                            Label(String(format: "Cmp %.1fGB", engine.memoryCompressedGB), systemImage: "archivebox.fill")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        InfoButton(text: "App: Active + inactive pages — memory currently in use or recently used by apps.\n\nWired: Locked in RAM by the kernel and drivers. Cannot be paged out to disk.\n\nCompressed: Pages compressed by macOS memory pressure system to free up physical RAM. High compressed memory is normal; it becomes swap when compression is no longer enough.\n\nSwap: Data written to disk because RAM was full. Persistent high swap usage indicates you need more RAM.")
                    }
                    Text("Swap used: \(String(format: "%.2f", engine.swapUsedGB)) GB")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SectionCard {
                ProcessListView(title: "Top Memory", icon: "memorychip", color: MetricTheme.memory, processes: engine.topMemoryProcesses, unit: "%", engine: engine)
            }
            Spacer()
        }
    }
}

// MARK: - Network

struct NetworkDetailView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var style: ChartDisplayStyle = .area

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Network", systemImage: MetricTheme.icon(for: .network))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MetricTheme.networkDown)
                Spacer()
                ChartStylePicker(style: $style)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Circle().fill(engine.isConnected ? Color.green : Color.red).frame(width: 9, height: 9)
                        Text(engine.isConnected ? "Connected — \(engine.connectionType)" : "No connection")
                            .font(.system(size: 16, weight: .semibold, design: .rounded))
                        if engine.isVPNActive {
                            Label("VPN", systemImage: "lock.shield.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.green)
                        }
                        Spacer()
                        InfoButton(text: "Local IPs are read from the system network interfaces.\n\nVPN is detected by the presence of utun, ppp, or ipsec interfaces.\n\nPublic IP is fetched from api.ipify.org over HTTPS. Only your outbound request is sent — no other data. Refreshed every 5 minutes.\n\nConnectivity check is an HTTPS HEAD request to Apple's captive portal endpoint (captive.apple.com). This respects your system proxy settings. True ICMP ping requires root on macOS, so this is used instead.")
                    }
                    ForEach(engine.localInterfaces) { iface in
                        CopyableIPRow(label: iface.name, value: iface.address)
                    }
                    Divider()
                    CopyableIPRow(label: "Public IP", value: engine.publicIP ?? "Looking up…")
                }
            }

            if let rssi = engine.wifiRSSI {
                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Label(engine.wifiSSID ?? "Wi-Fi", systemImage: "wifi")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            InfoButton(text: "Signal strength is measured in dBm (decibel-milliwatts) — a negative number where closer to zero is stronger.\n\n• Excellent (−50 dBm or better): Ideal. Full speed, no drops.\n• Good (−50 to −65 dBm): Reliable for video calls and large transfers.\n• Fair (−65 to −75 dBm): Usable but may slow down. Consider moving closer to your router.\n• Weak (below −75 dBm): Prone to disconnects and slow speeds.\n\nRead from CoreWLAN — same source as the macOS menu bar WiFi indicator.")
                        }
                        WiFiSignalBars(rssi: rssi)
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("Connectivity Check", systemImage: "waveform.path.ecg")
                            .font(.subheadline.weight(.semibold))
                        Spacer()
                        if let ms = engine.pingLatencyMs {
                            Text(String(format: "%.0f ms", ms))
                                .font(.system(size: 16, weight: .bold, design: .rounded))
                                .foregroundStyle(ms < 100 ? .green : ms < 300 ? .orange : .red)
                        } else {
                            Text("Timeout").font(.caption).foregroundStyle(.red)
                        }
                    }
                    MetricChart(values: engine.pingHistory, unit: "ms", showAxes: true, color: .teal) { String(format: "%.0fms", $0) }
                        .frame(height: 60)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("↓ \(formatSpeed(engine.downloadSpeedKBps))", systemImage: "arrow.down")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(MetricTheme.networkDown)
                    MetricChart(values: engine.downloadHistory, unit: "KB/s", color: MetricTheme.networkDown, style: style, valueFormatter: formatSpeed)
                        .frame(height: 90)
                }
            }
            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Label("↑ \(formatSpeed(engine.uploadSpeedKBps))", systemImage: "arrow.up")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(MetricTheme.networkUp)
                    MetricChart(values: engine.uploadHistory, unit: "KB/s", color: MetricTheme.networkUp, style: style, valueFormatter: formatSpeed)
                        .frame(height: 90)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Top Network Usage", systemImage: "network")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(MetricTheme.networkDown)
                    if engine.topNetworkProcesses.isEmpty {
                        Text("Measuring…").font(.caption).foregroundStyle(.secondary)
                    } else {
                        ForEach(engine.topNetworkProcesses) { proc in
                            HStack {
                                Text(proc.name).font(.caption).lineLimit(1)
                                Spacer()
                                Text(formatSpeed(proc.value)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private func formatSpeed(_ kbps: Double) -> String {
        kbps > 1024 ? String(format: "%.2f MB/s", kbps / 1024) : String(format: "%.1f KB/s", kbps)
    }
}

// MARK: - Disk

struct DiskDetailView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var style: ChartDisplayStyle = .area

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Disk", systemImage: MetricTheme.icon(for: .disk))
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MetricTheme.disk)
                Spacer()
                ChartStylePicker(style: $style)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(String(format: "%.1f", engine.diskTotalGB - engine.diskFreeGB)) GB used / \(String(format: "%.1f", engine.diskTotalGB)) GB")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .foregroundStyle(MetricTheme.disk)
                    Text("Read: \(formatSpeed(engine.diskReadKBps))   Write: \(formatSpeed(engine.diskWriteKBps))")
                        .font(.caption).foregroundStyle(.secondary)
                    MetricChart(values: engine.diskReadHistory, unit: "KB/s", color: MetricTheme.disk, style: style, valueFormatter: formatSpeed)
                        .frame(height: 80)
                    MetricChart(values: engine.diskWriteHistory, unit: "KB/s", color: MetricTheme.disk.opacity(0.7), style: style, valueFormatter: formatSpeed)
                        .frame(height: 80)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Volumes").font(.subheadline.weight(.semibold))
                    let visibleVolumes = engine.volumes.filter { engine.showRemovableVolumes || !$0.isRemovable }
                    ForEach(visibleVolumes) { volume in
                        HStack {
                            Text(volume.name).font(.caption).lineLimit(1)
                            if volume.isRemovable { Text("(Removable)").font(.caption2).foregroundStyle(.secondary) }
                            Spacer()
                            Text(String(format: "%.0f / %.0f GB", volume.totalGB - volume.freeGB, volume.totalGB))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private func formatSpeed(_ kbps: Double) -> String {
        kbps > 1024 ? String(format: "%.2f MB/s", kbps / 1024) : String(format: "%.1f KB/s", kbps)
    }
}

// MARK: - GPU & Displays

struct GPUDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("GPU & Displays", systemImage: "cube.transparent")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.cyan)
                Spacer()
                InfoButton(text: "GPU utilization percentage is not available through any public macOS API on Apple Silicon. Apple's IOKit SMC interface blocks access to GPU load counters for user-space processes.\n\nThird-party tools that show GPU % use private, entitled APIs or kernel extensions that require special signing. The Metal information shown here (working set size, power mode) is the maximum available through the public API.")
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(engine.gpuName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    row("Location", engine.gpuLocation)
                    row("Max working set", String(format: "%.1f GB", engine.gpuRecommendedMemoryGB))
                    row("Power mode", engine.gpuIsLowPower ? "Low power" : "High performance")
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Displays").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
                        } label: {
                            Label("Arrange…", systemImage: "rectangle.3.group")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    if engine.displays.isEmpty {
                        Text("No display info available")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(engine.displays) { display in
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(display.name).font(.caption.weight(.medium))
                                Text("\(display.width) × \(display.height)  @\(display.refreshRateHz) Hz  (\(display.scaleFactor == 2 ? "Retina" : String(format: "%.0f×", display.scaleFactor)))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if display.isMain {
                                Text("Main")
                                    .font(.caption2)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.cyan.opacity(0.15), in: Capsule())
                                    .foregroundStyle(.cyan)
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
        }
    }
}

// MARK: - Battery

struct BatteryDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Battery", systemImage: "battery.100percent")
                .font(.title2.weight(.semibold))
                .foregroundStyle(MetricTheme.battery)

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    if let percent = engine.batteryPercent {
                        Text("\(percent)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(MetricTheme.battery)
                    }
                    Text(engine.batteryIsCharging ? "Charging" : "On battery")
                        .font(.caption).foregroundStyle(.secondary)
                    if let minutes = engine.batteryTimeRemainingMinutes {
                        Text("\(minutes / 60)h \(minutes % 60)m \(engine.batteryIsCharging ? "to full" : "remaining")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Health").font(.subheadline.weight(.semibold))
                        Spacer()
                        InfoButton(text: "Capacity %: NominalChargeCapacity ÷ DesignCapacity × 100. This shows how much of the original battery capacity remains.\n\nCycle count: Each full charge/discharge cycle counts as one. Apple considers batteries at peak performance for 1000 cycles (MacBook Pro/Air M-series). After that, capacity may be below 80%.\n\nCondition 'Normal' means the battery is performing within expected parameters. 'Service Recommended' means capacity has dropped significantly and Apple recommends a replacement.")
                    }
                    if let health = engine.batteryHealthPercent {
                        HStack {
                            Text("Capacity vs. design").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.0f%%", health)).font(.caption.monospacedDigit())
                        }
                    }
                    HStack {
                        Text("Condition").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(engine.batteryCondition).font(.caption.monospacedDigit())
                    }
                    if let cycles = engine.batteryCycleCount {
                        HStack {
                            Text("Cycle count").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            if let design = engine.batteryDesignCycleCount {
                                Text("\(cycles) / \(design)").font(.caption.monospacedDigit())
                            } else {
                                Text("\(cycles)").font(.caption.monospacedDigit())
                            }
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Electrical").font(.subheadline.weight(.semibold))
                        Spacer()
                        InfoButton(text: "Temperature: Read from AppleSmartBattery IORegistry — no special privileges needed. This is the battery cell temperature, not the CPU temperature.\n\nVoltage: Current battery terminal voltage in volts.\n\nCurrent: Positive = charging (current flowing in). Negative = discharging (current flowing out). Values are in milliamps (mA).\n\nAll values come from the AppleSmartBattery driver which is always accessible without entitlements.")
                    }
                    if let temp = engine.batteryTemperatureC {
                        HStack {
                            Text("Temperature").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f°C", temp)).font(.caption.monospacedDigit())
                        }
                    }
                    if let voltage = engine.batteryVoltage {
                        HStack {
                            Text("Voltage").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.2f V", voltage)).font(.caption.monospacedDigit())
                        }
                    }
                    if let amperage = engine.batteryAmperage {
                        HStack {
                            Text("Current").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(amperage) mA").font(.caption.monospacedDigit())
                        }
                    }
                }
            }
            Spacer()
        }
    }
}

// MARK: - Bluetooth

struct BluetoothDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("Bluetooth", systemImage: "dot.radiowaves.left.and.right")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.blue)
                Spacer()
                InfoButton(text: "Paired devices are read from the IOBluetooth framework — all devices you have ever paired, whether connected or not.\n\nBattery percentage is read from the IOHIDDevice registry for devices that expose it (Apple peripherals: AirPods, Magic Mouse, Magic Keyboard, etc.). Third-party peripherals may not expose battery data.")
            }

            if engine.bluetoothAuthState != .allowedAlways {
                SectionCard {
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.largeTitle).foregroundStyle(.blue)
                        Text("Bluetooth Access Required")
                            .font(.subheadline.weight(.semibold))
                        Text(engine.bluetoothAuthState == .denied || engine.bluetoothAuthState == .restricted
                             ? "Access was denied. Go to System Settings → Privacy & Security → Bluetooth to enable it."
                             : "Allow Performance Monitor to read your paired Bluetooth devices.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if engine.bluetoothAuthState == .denied || engine.bluetoothAuthState == .restricted {
                            Button("Open Privacy Settings") {
                                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth")!)
                            }
                            .buttonStyle(.borderedProminent).controlSize(.regular)
                        } else {
                            Button("Grant Bluetooth Access") { engine.requestBluetoothAccess() }
                                .buttonStyle(.borderedProminent).controlSize(.regular)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            } else {
                SectionCard {
                    VStack(alignment: .leading, spacing: 10) {
                        let connected = engine.bluetoothDevices.filter { $0.isConnected }
                        let disconnected = engine.bluetoothDevices.filter { !$0.isConnected }

                        if engine.bluetoothDevices.isEmpty {
                            Text("No paired devices found.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            if !connected.isEmpty {
                                Text("Connected").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(connected) { device in
                                    BluetoothDeviceRow(device: device)
                                }
                            }
                            if !disconnected.isEmpty {
                                if !connected.isEmpty { Divider() }
                                Text("Not connected").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                                ForEach(disconnected) { device in
                                    BluetoothDeviceRow(device: device)
                                }
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }
}

struct BluetoothDeviceRow: View {
    let device: BluetoothDevice

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: device.icon)
                .font(.system(size: 13))
                .foregroundStyle(device.isConnected ? .blue : .secondary)
                .frame(width: 18)
            Text(device.name).font(.caption).lineLimit(1)
            Spacer()
            if let pct = device.batteryPercent {
                HStack(spacing: 3) {
                    Image(systemName: "battery.75percent").font(.caption2)
                    Text("\(pct)%").font(.caption.monospacedDigit())
                }
                .foregroundStyle(pct < 20 ? .red : .secondary)
            }
            if !device.isConnected {
                Circle().fill(Color.secondary.opacity(0.3)).frame(width: 7, height: 7)
            }
        }
    }
}

// MARK: - Shared helpers

// MARK: - WiFi Signal Bars

struct WiFiSignalBars: View {
    let rssi: Int   // dBm, e.g. -55

    private var bars: Int {
        if rssi >= -50 { return 4 }
        if rssi >= -65 { return 3 }
        if rssi >= -75 { return 2 }
        return 1
    }

    private var label: String {
        switch bars {
        case 4: return "Excellent"
        case 3: return "Good"
        case 2: return "Fair"
        default: return "Weak"
        }
    }

    private var color: Color {
        switch bars {
        case 4, 3: return .green
        case 2: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // 4 bars of increasing height
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= bars ? color : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: CGFloat(i) * 5 + 4)
                }
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text("\(rssi) dBm")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
    }
}

struct CopyableIPRow: View {
    let label: String
    let value: String
    @State private var copied = false

    var body: some View {
        HStack {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

private struct WindowFloatAccessor: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.level = .floating
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            // Force every detail window to exactly the same content size.
            // SwiftUI's frame/defaultSize hints are unreliable when windows have
            // been resized or when content height differs between tabs.
            window.setContentSize(NSSize(width: 420, height: 540))
            window.styleMask.remove(.resizable)
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
