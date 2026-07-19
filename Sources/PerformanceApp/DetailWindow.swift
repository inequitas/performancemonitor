import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

struct DetailWindow: View {
    let kind: MetricsEngine.Panel
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        ScrollView {
            Group {
                switch kind {
                case .cpu:       CPUDetailView(engine: engine)
                case .memory:    MemoryDetailView(engine: engine)
                case .network:   NetworkDetailView(engine: engine)
                case .disk:      DiskDetailView(engine: engine)
                case .gpu:       GPUDetailView(engine: engine)
                case .battery:   BatteryDetailView(engine: engine)
                case .bluetooth: BluetoothDetailView(engine: engine)
                case .thermal:   ThermalDetailView(engine: engine)
                }
            }
            .padding()
            .frame(width: detailWindowWidth, alignment: .leading)
        }
        .frame(width: detailWindowWidth, height: detailWindowHeight)
        .navigationTitle(kind.title)
        .background(.regularMaterial)
        .background(WindowFloatAccessor(engine: engine))
        .preferredColorScheme(engine.settings.preferredColorScheme)
    }
}

let detailWindowWidth: CGFloat = 420
let detailWindowHeight: CGFloat = 540

func formatSpeed(_ kbps: Double) -> String {
    kbps > 1024 ? String(format: "%.2f MB/s", kbps / 1024) : String(format: "%.1f KB/s", kbps)
}

func batterySystemImage(_ pct: Int, charging: Bool = false) -> String {
    let suffix = charging ? ".bolt" : ""
    switch pct {
    case 76...: return "battery.100percent\(suffix)"
    case 51...: return "battery.75percent\(suffix)"
    case 26...: return "battery.50percent\(suffix)"
    case 11...: return "battery.25percent\(suffix)"
    default:    return "battery.0percent\(suffix)"
    }
}

func detailRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.caption.monospacedDigit())
    }
}

func iconDetailRow(_ icon: String, color: Color, label: String, value: String, valueColor: Color = .primary) -> some View {
    HStack {
        Image(systemName: icon)
            .font(.caption)
            .foregroundStyle(color)
            .frame(width: 16)
        Text(label).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.caption.monospacedDigit()).foregroundStyle(valueColor)
    }
}

struct EarbudBatteryPill: View {
    let label: String
    let pct: Int
    init(_ label: String, _ pct: Int) { self.label = label; self.pct = pct }
    var body: some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text("\(pct)%").font(.caption2.monospacedDigit()).foregroundStyle(pct < 20 ? .red : .secondary)
        }
    }
}

// Shared butterfly bar chart. sharedMax is passed in so axis labels in the
// parent always match the scale the chart is actually using.
struct ButterflyBarChart: View {
    let upHistory:    [Double]
    let downHistory:  [Double]
    let upColor:      Color
    let downColor:    Color
    let sharedMax:    Double
    var displayCount: Int = 60

    private var paddedUp: [Double] {
        let slice = Array(upHistory.suffix(displayCount))
        return slice + Array(repeating: 0.0, count: displayCount - slice.count)
    }
    private var paddedDown: [Double] {
        let slice = Array(downHistory.suffix(displayCount))
        return slice + Array(repeating: 0.0, count: displayCount - slice.count)
    }

    var body: some View {
        Chart {
            ForEach(Array(paddedUp.enumerated()), id: \.offset) { i, val in
                BarMark(x: .value("t", i), yStart: .value("v", 0.0), yEnd: .value("v", val),
                        width: .inset(1))
                    .foregroundStyle(upColor)
            }
            ForEach(Array(paddedDown.enumerated()), id: \.offset) { i, val in
                BarMark(x: .value("t", i), yStart: .value("v", -val), yEnd: .value("v", 0.0),
                        width: .inset(1))
                    .foregroundStyle(downColor)
            }
        }
        .chartYScale(domain: -sharedMax ... sharedMax)
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: [0.0]) {
                AxisGridLine().foregroundStyle(Color.primary.opacity(0.25))
            }
        }
    }
}


struct NetworkButterflyChart: View {
    let downloadHistory: [Double]
    let uploadHistory:   [Double]
    let downloadSpeed:   Double
    let uploadSpeed:     Double

    private var sharedMax: Double { absoluteMax(downloadHistory, uploadHistory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Throughput", systemImage: "arrow.up.arrow.down")
                .font(.subheadline.weight(.semibold))
            HStack {
                Label(formatSpeed(downloadSpeed), systemImage: "arrow.down")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MetricTheme.networkDown)
                Spacer()
                Label(formatSpeed(uploadSpeed), systemImage: "arrow.up")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(MetricTheme.networkUp)
            }
            HStack(spacing: 4) {
                VStack(spacing: 0) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatSpeed(sharedMax)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSpeed(sharedMax / 2)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 90)
                    Text(formatSpeed(0)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: 14)
                    VStack(alignment: .trailing, spacing: 0) {
                        Spacer()
                        Text(formatSpeed(sharedMax / 2)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSpeed(sharedMax)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(height: 90)
                }
                .frame(width: 56)
                VStack(spacing: 0) {
                    MetricChart(values: downloadHistory, fixedMax: sharedMax, showAxes: false, showGridLines: true, fillFrame: true, color: MetricTheme.networkDown, style: .area) { formatSpeed($0) }
                        .frame(height: 90)
                    Color.primary.opacity(0.25).frame(height: 1).frame(height: 14)
                    MetricChart(values: uploadHistory, fixedMax: sharedMax, showAxes: false, showGridLines: true, fillFrame: true, color: MetricTheme.networkUp, style: .area) { formatSpeed($0) }
                        .frame(height: 90)
                        .scaleEffect(y: -1)
                }
                .frame(height: 194)
            }
        }
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
                    if !paused { frozenList = Array(processes.prefix(engine.settings.topProcessCount)) }
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
                ForEach(displayed.prefix(engine.settings.topProcessCount)) { proc in
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
        .alert(
            "Quit \(pendingKill?.name ?? "process")?",
            isPresented: Binding(get: { pendingKill != nil }, set: { _ in pendingKill = nil }),
            presenting: pendingKill
        ) { proc in
            Button("Cancel", role: .cancel) { }
            Button("Quit", role: .destructive) {
                engine.terminateProcess(pid: proc.pid)
                paused = false
            }
        } message: { proc in
            Text("This sends a quit signal to the process (PID \(proc.pid)). Unsaved work may be lost.")
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
                Label("CPU", systemImage: MetricsEngine.Panel.cpu.icon)
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
                Label("Memory", systemImage: MetricsEngine.Panel.memory.icon)
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
    @State private var expandedInterfaces: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Network", systemImage: MetricsEngine.Panel.network.icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(MetricTheme.networkDown)

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
                        interfaceRow(iface)
                    }
                    Divider()
                    CopyableIPRow(icon: "globe", label: "Public IP", value: engine.publicIP ?? "Looking up…")
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
                NetworkButterflyChart(
                    downloadHistory: engine.downloadHistory,
                    uploadHistory: engine.uploadHistory,
                    downloadSpeed: engine.downloadSpeedKBps,
                    uploadSpeed: engine.uploadSpeedKBps
                )
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

    @ViewBuilder
    private func interfaceRow(_ iface: LocalInterface) -> some View {
        let isExpanded = expandedInterfaces.contains(iface.id)
        let suffix = iface.prefixLength.map { "/\($0)" } ?? ""

        VStack(alignment: .leading, spacing: 4) {
            Button {
                withAnimation(.easeInOut(duration: 0.18)) {
                    if isExpanded { expandedInterfaces.remove(iface.id) }
                    else          { expandedInterfaces.insert(iface.id) }
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: iface.icon)
                        .font(.caption2)
                        .foregroundStyle(iface.isPrimary ? Color.green : Color.secondary)
                        .frame(width: 14)
                    Text(iface.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if !isExpanded {
                        Text(iface.address + suffix)
                            .font(.caption.monospacedDigit())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 4) {
                    CopyableIPRow(label: "IP", value: iface.address)
                    if let mask = iface.subnetMask {
                        CopyableIPRow(label: "Subnet", value: mask)
                    }
                    if let gw = iface.gateway {
                        CopyableIPRow(label: "Gateway", value: gw)
                    }
                    ForEach(engine.dnsServers, id: \.self) { dns in
                        CopyableIPRow(icon: "server.rack", label: "DNS", value: dns)
                    }
                }
                .padding(.leading, 22)
            }
        }
    }
}

// MARK: - Disk

private struct DiskButterflyChart: View {
    let readHistory:  [Double]
    let writeHistory: [Double]
    let readSpeed:    Double
    let writeSpeed:   Double

    private var sharedMax: Double { absoluteMax(readHistory, writeHistory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(formatSpeed(readSpeed), systemImage: "arrow.down")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.indigo)
                Text("Read").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Write").font(.caption).foregroundStyle(.secondary)
                Label(formatSpeed(writeSpeed), systemImage: "arrow.up")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.purple)
            }
            HStack(spacing: 4) {
                VStack(spacing: 0) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatSpeed(sharedMax)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSpeed(sharedMax / 2)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 90)
                    Text(formatSpeed(0)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: 14)
                    VStack(alignment: .trailing, spacing: 0) {
                        Spacer()
                        Text(formatSpeed(sharedMax / 2)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSpeed(sharedMax)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(height: 90)
                }
                .frame(width: 56)
                VStack(spacing: 0) {
                    MetricChart(values: readHistory, fixedMax: sharedMax, showAxes: false, showGridLines: true, fillFrame: true, color: .indigo, style: .area) { formatSpeed($0) }
                        .frame(height: 90)
                    Color.primary.opacity(0.25).frame(height: 1).frame(height: 14)
                    MetricChart(values: writeHistory, fixedMax: sharedMax, showAxes: false, showGridLines: true, fillFrame: true, color: .purple, style: .area) { formatSpeed($0) }
                        .frame(height: 90)
                        .scaleEffect(y: -1)
                }
                .frame(height: 194)
            }
        }
    }
}

struct DiskDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Disk", systemImage: MetricsEngine.Panel.disk.icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(MetricTheme.disk)

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Storage").font(.subheadline.weight(.semibold))
                        Spacer()
                        if let smart = engine.diskSmartStatus {
                            let ok = smart == "Verified"
                            Label(ok ? "SMART OK" : smart, systemImage: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ok ? .green : .red)
                        }
                    }
                    let visibleVolumes = engine.volumes.filter { engine.settings.showRemovableVolumes || !$0.isRemovable }
                    ForEach(visibleVolumes) { volume in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(volume.name).font(.caption).lineLimit(1)
                                if volume.isRemovable { Text("Removable").font(.caption2).foregroundStyle(.secondary) }
                            }
                            DiskUsageBar(used: volume.totalGB - volume.freeGB, total: volume.totalGB)
                            HStack {
                                Text(String(format: "%.1f GB used", volume.totalGB - volume.freeGB))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f GB free", volume.freeGB))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            SectionCard {
                DiskButterflyChart(
                    readHistory:  engine.diskReadHistory,
                    writeHistory: engine.diskWriteHistory,
                    readSpeed:    engine.diskReadKBps,
                    writeSpeed:   engine.diskWriteKBps
                )
            }

            if !engine.topDiskProcesses.isEmpty {
                SectionCard {
                    ProcessListView(title: "Top Disk I/O", icon: "internaldrive", color: MetricTheme.disk,
                                    processes: engine.topDiskProcesses, unit: " KB/s", engine: engine)
                }
            }

            Spacer()
        }
    }
}

// MARK: - Disk storage helpers

private struct DiskUsageBar: View {
    let used: Double
    let total: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.indigo)
                    .frame(width: max(2, geo.size.width * used / max(total, 1)))
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}

// MARK: - GPU & Displays

private func displayIcon(_ display: DisplayInfo) -> String {
    if display.isBuiltIn { return "laptopcomputer" }
    let ratio = Double(display.width) / Double(display.height)
    if ratio >= 2.3 { return "rectangle.ratio.16.to.9.fill" }
    return "display"
}

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
                    detailRow("Location", engine.gpuLocation)
                    detailRow("Max working set", String(format: "%.1f GB", engine.gpuRecommendedMemoryGB))
                    detailRow("Power mode", engine.gpuIsLowPower ? "Low power" : "High performance")
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
                    ForEach(engine.displays) { info in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: displayIcon(info))
                                    .font(.system(size: 15))
                                    .foregroundStyle(.cyan.opacity(0.8))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(info.name).font(.caption.weight(.medium))
                                    Text("\(info.width) × \(info.height)  @\(info.refreshRateHz) Hz  (\(info.scaleFactor == 2 ? "Retina" : String(format: "%.0f×", info.scaleFactor)))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if !info.colorProfile.isEmpty {
                                        Text(info.colorProfile)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if !info.connectionType.isEmpty {
                                        Text(info.connectionType)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    if info.isMain {
                                        Text("Main")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.cyan.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.cyan)
                                    }
                                    if info.trueTone {
                                        Text("True Tone")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.yellow.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.yellow)
                                    }
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

// MARK: - Battery

struct BatteryDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Battery", systemImage: batterySystemImage(
                engine.batteryPercent ?? 100,
                charging: engine.batteryIsCharging
            ))
                .font(.title2.weight(.semibold))
                .foregroundStyle(MetricTheme.battery)

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    if let percent = engine.batteryPercent {
                        Text("\(percent)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(MetricTheme.battery)
                    }
                    detailRow("Source", engine.powerSourceName)
                    detailRow("State", engine.batteryIsCharging ? "Charging" : "Discharging")
                    if let minutes = engine.batteryTimeRemainingMinutes {
                        detailRow(engine.batteryIsCharging ? "Time to full" : "Time remaining",
                                  "\(minutes / 60)h \(minutes % 60)m")
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
                        detailRow("Capacity vs. design", String(format: "%.0f%%", health))
                    }
                    detailRow("Condition", engine.batteryCondition)
                    if let cycles = engine.batteryCycleCount {
                        detailRow("Cycle count", engine.batteryDesignCycleCount.map { "\(cycles) / \($0)" } ?? "\(cycles)")
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
                    if let v = engine.batteryVoltage, let a = engine.batteryAmperage {
                        let watts = v * abs(Double(a)) / 1000
                        detailRow(engine.batteryIsCharging ? "Input power" : "Draw",
                                  String(format: "%.1f W", watts))
                    }
                    if let temp = engine.batteryTemperatureC {
                        HStack {
                            Text("Temperature").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f°C", temp))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(MetricTheme.sensorTempColor(temp, category: "Battery"))
                        }
                    }
                    if let voltage = engine.batteryVoltage {
                        detailRow("Voltage", String(format: "%.2f V", voltage))
                    }
                    if let amperage = engine.batteryAmperage {
                        detailRow("Current", "\(amperage) mA")
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
                    let isDenied = engine.bluetoothAuthState == .denied || engine.bluetoothAuthState == .restricted
                    VStack(spacing: 12) {
                        Image(systemName: "hand.raised.fill")
                            .font(.largeTitle).foregroundStyle(.blue)
                        Text("Bluetooth Access Required")
                            .font(.subheadline.weight(.semibold))
                        Text(isDenied
                             ? "Access was denied. Go to System Settings → Privacy & Security → Bluetooth to enable it."
                             : "Allow Performance Monitor to read your paired Bluetooth devices.")
                            .font(.caption).foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                        if isDenied {
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

// MARK: - Thermal & Fans

struct ThermalDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Thermal & Fans", systemImage: "thermometer.medium")
                .font(.title2.weight(.semibold))
                .foregroundStyle(engine.thermalState.color)

            // Thermal pressure
            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thermal Pressure").font(.subheadline.weight(.semibold))
                        Spacer()
                        InfoButton(text: "macOS reports four thermal pressure levels:\n\n• Nominal — system operating normally.\n• Fair — some power reduction to prevent overheating.\n• Serious — significant throttling in effect.\n• Critical — aggressive throttling; performance severely impacted.\n\nThis is read from ProcessInfo.thermalState — the same value macOS uses internally to throttle workloads.")
                    }
                    HStack(spacing: 8) {
                        Circle().fill(engine.thermalState.color).frame(width: 10, height: 10)
                        Text(engine.thermalState.label)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(engine.thermalState.color)
                    }
                }
            }

            // Temperatures — each category expandable to individual sensors
            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperatures").font(.subheadline.weight(.semibold))
                        Spacer()
                        InfoButton(text: "Read from the System Management Controller (SMC) via IOKit.\n\nCPU and GPU values shown are averages across all cluster sensors. Tap a row to expand individual readings.\n\nBattery temperature is read from the AppleSmartBattery IORegistry entry.")
                    }

                    let groups = Dictionary(grouping: engine.extendedTemperatures, by: \.category)
                    let cpuSensors      = (groups["CPU"]      ?? []).sorted { $0.label < $1.label }
                    let gpuSensors      = (groups["GPU"]      ?? []).sorted { $0.label < $1.label }
                    let trackpadSensors = (groups["Trackpad"] ?? []).sorted { $0.label < $1.label }

                    if let avg = engine.cpuTemperatureC {
                        SensorCategoryRow(
                            icon: "cpu", iconColor: MetricTheme.cpu, label: "CPU", avgCelsius: avg,
                            sensors: cpuSensors.map { ($0.label, $0.celsius) },
                            colorFn: { MetricTheme.sensorTempColor($0, category: "CPU") }
                        )
                    }
                    if let avg = engine.gpuTemperatureC {
                        SensorCategoryRow(
                            icon: "cube.transparent", iconColor: .cyan, label: "GPU", avgCelsius: avg,
                            sensors: gpuSensors.map { ($0.label, $0.celsius) },
                            colorFn: { MetricTheme.sensorTempColor($0, category: "GPU") }
                        )
                    }
                    if let bat = engine.batteryTemperatureC {
                        SensorCategoryRow(
                            icon: "battery.75percent", iconColor: MetricTheme.battery, label: "Battery",
                            avgCelsius: bat, sensors: [],
                            colorFn: { MetricTheme.sensorTempColor($0, category: "Battery") }
                        )
                    }

                    // Storage group
                    let storageSensors = (groups["Storage"] ?? []).sorted { $0.label < $1.label }
                    if !storageSensors.isEmpty {
                        let avg = storageSensors.map(\.celsius).reduce(0, +) / Double(storageSensors.count)
                        SensorCategoryRow(
                            icon: "internaldrive", iconColor: .indigo, label: "Storage", avgCelsius: avg,
                            sensors: storageSensors.map { ($0.label, $0.celsius) },
                            colorFn: { MetricTheme.sensorTempColor($0, category: "Storage") }
                        )
                    }

                    // System group (starts expanded) — Trackpad + board sensors
                    let systemDisplaySensors: [(label: String, celsius: Double)] = {
                        var result: [(label: String, celsius: Double)] = []
                        if !trackpadSensors.isEmpty {
                            if trackpadSensors.count <= 3 {
                                result += trackpadSensors.map { ($0.label, $0.celsius) }
                            } else {
                                let avg = trackpadSensors.map(\.celsius).reduce(0, +) / Double(trackpadSensors.count)
                                result.append(("Trackpad", avg))
                            }
                        }
                        result += (groups["System"] ?? []).sorted { $0.label < $1.label }.map { ($0.label, $0.celsius) }
                        return result
                    }()
                    if !systemDisplaySensors.isEmpty {
                        let avg = systemDisplaySensors.map(\.celsius).reduce(0, +) / Double(systemDisplaySensors.count)
                        SensorCategoryRow(
                            icon: "thermometer", iconColor: .orange, label: "System", avgCelsius: avg,
                            sensors: systemDisplaySensors,
                            colorFn: { MetricTheme.sensorTempColor($0, category: "System") },
                            initiallyExpanded: true
                        )
                    }

                    // Memory group
                    let memorySensors = (groups["Memory"] ?? []).sorted { $0.label < $1.label }
                    if !memorySensors.isEmpty {
                        let avg = memorySensors.map(\.celsius).reduce(0, +) / Double(memorySensors.count)
                        SensorCategoryRow(
                            icon: "memorychip", iconColor: MetricTheme.memory, label: "Memory", avgCelsius: avg,
                            sensors: memorySensors.map { ($0.label, $0.celsius) },
                            colorFn: { MetricTheme.sensorTempColor($0, category: "Memory") }
                        )
                    }

                    if engine.cpuTemperatureC == nil && engine.gpuTemperatureC == nil && engine.extendedTemperatures.isEmpty {
                        Text("No temperature sensors found for this Mac model.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // Fan speeds (+ airflow temperatures where available)
            if !engine.fans.isEmpty {
                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Fans").font(.subheadline.weight(.semibold))
                            Spacer()
                            InfoButton(text: "Fan speed is read from the SMC via IOKit.\n\nActual: current measured RPM.\nMin/Max: hardware-defined speed range for this fan.\nAirflow: intake air temperature sensor near each fan.")
                        }
                        let airflow = engine.extendedTemperatures.filter { $0.category == "Airflow" }
                        ForEach(engine.fans) { fan in
                            VStack(alignment: .leading, spacing: 6) {
                                if engine.fans.count > 1 {
                                    Label(fan.label, systemImage: "fan.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                detailRow("Speed", "\(fan.actual) RPM")
                                detailRow("Range", "\(fan.min) – \(fan.max) RPM")
                                if fan.max > fan.min {
                                    let progress = Double(fan.actual - fan.min) / Double(fan.max - fan.min)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.secondary.opacity(0.15))
                                                .frame(height: 5)
                                            Capsule().fill(engine.thermalState.color)
                                                .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)), height: 5)
                                        }
                                    }
                                    .frame(height: 5)
                                }
                                // Airflow sensor matched to this fan by label (Left/Right)
                                if let a = airflow.first(where: { $0.label.lowercased().contains(fan.label.lowercased()) }) {
                                    detailRow("Airflow", String(format: "%.1f°C", a.celsius))
                                }
                            }
                            if fan.id < engine.fans.count - 1 { Divider() }
                        }
                    }
                }
            }

            Spacer()
        }
    }

}

private struct SensorCategoryRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let avgCelsius: Double
    let sensors: [(label: String, celsius: Double)]
    let colorFn: (Double) -> Color

    @State private var expanded: Bool

    init(icon: String, iconColor: Color, label: String, avgCelsius: Double,
         sensors: [(label: String, celsius: Double)], colorFn: @escaping (Double) -> Color,
         initiallyExpanded: Bool = false) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.avgCelsius = avgCelsius
        self.sensors = sensors
        self.colorFn = colorFn
        _expanded = State(initialValue: initiallyExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if sensors.count > 1 {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
            } label: {
                HStack(spacing: 8) {
                    // Note: contentShape below ensures the Spacer and chevron are tappable
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 22, height: 22)
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f°C", avgCelsius))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(colorFn(avgCelsius))
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .opacity(sensors.count > 1 ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sensors, id: \.label) { sensor in
                        HStack {
                            Text(sensor.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f°C", sensor.celsius))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(colorFn(sensor.celsius))
                        }
                        .padding(.leading, 30)
                    }
                }
                .padding(.top, 6)
            }
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
            if device.batteryLeft != nil || device.batteryRight != nil || device.batteryCase != nil {
                HStack(spacing: 4) {
                    if let l = device.batteryLeft  { EarbudBatteryPill("L", l) }
                    if let r = device.batteryRight { EarbudBatteryPill("R", r) }
                    if let c = device.batteryCase  { EarbudBatteryPill("Case", c) }
                }
            } else if let pct = device.batteryPercent {
                HStack(spacing: 3) {
                    Image(systemName: batterySystemImage(pct)).font(.caption2)
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

    private var bars: Int { WiFiSignal.bars(forRSSI: rssi) }

    private var label: String { WiFiSignal.label(forBars: bars) }

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
    let icon: String
    let label: String
    let value: String
    let iconColor: Color
    @State private var copied = false

    init(icon: String = "network", label: String, value: String, iconColor: Color = .secondary) {
        self.icon = icon
        self.label = label
        self.value = value
        self.iconColor = iconColor
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(iconColor)
                .frame(width: 14)
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

// Detail windows are standard titled windows, so opening one makes macOS show
// a Dock icon regardless of the accessory activation policy. Restore .accessory
// on close (if Show in Dock is off and this was the last visible window) the
// same way SettingsView's WindowFocuser does — otherwise opening a metric card
// permanently pins the Dock icon for the rest of the session.
private struct WindowFloatAccessor: NSViewRepresentable {
    let engine: MetricsEngine

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
            window.setContentSize(NSSize(width: detailWindowWidth, height: detailWindowHeight))
            window.styleMask.remove(.resizable)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak engine] _ in
                Task { @MainActor in
                    guard let engine, !engine.settings.showInDock else { return }
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
