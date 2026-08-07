import Foundation
import Darwin
import SwiftUI
import IOKit
import IOKit.storage
import IOKit.ps
import AppKit
import UserNotifications
import UniformTypeIdentifiers
import Metal
import Network
import IOBluetooth
import CoreBluetooth
import CoreWLAN
import SystemConfiguration
import PerformanceAppCore

@MainActor
final class MetricsEngine: ObservableObject {
    /// The live engine, for App Intents to read.
    ///
    /// Shortcuts runs an intent inside this process but hands it no reference to
    /// the object graph the app built, and the engine is deliberately not a
    /// singleton: `AppContainer` owns it so the scene never observes it. This is
    /// the one seam between the two. Weak, so it claims nothing about lifetime,
    /// and only ever read on the main actor.
    private(set) static weak var current: MetricsEngine?

    @Published var cpuUsagePercent: Double = 0
    @Published var cpuUserPercent: Double = 0
    @Published var cpuSystemPercent: Double = 0
    var cpuIdlePercent: Double { max(100 - cpuUsagePercent, 0) }
    @Published var loadAverages: (one: Double, five: Double, fifteen: Double) = (0, 0, 0)
    @Published var perCoreUsage: [Double] = []
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var swapUsedGB: Double = 0
    /// What macOS reports about memory pressure right now: 1 normal, 2 warning,
    /// 4 critical. Unlike `swapUsedGB`, which is a standing total left over from
    /// whenever memory was last tight, this describes the present.
    @Published var memoryPressureLevel: Int = 1
    /// Pages moving between memory and disk per second. Non-zero means paging is
    /// happening now, which is the part that makes a machine feel slow.
    @Published var swapPagesPerSecond: Double = 0
    @Published var memoryAppGB: Double = 0
    @Published var memoryWiredGB: Double = 0
    @Published var memoryCompressedGB: Double = 0

    @Published var downloadSpeedKBps: Double = 0
    @Published var uploadSpeedKBps: Double = 0

    @Published var cpuHistory: [Double] = []
    @Published var memoryHistory: [Double] = []
    @Published var downloadHistory: [Double] = []
    @Published var uploadHistory: [Double] = []

    @Published var diskFreeGB: Double = 0
    @Published var diskTotalGB: Double = 0
    @Published var diskReadKBps: Double = 0
    @Published var diskWriteKBps: Double = 0
    @Published var diskReadHistory: [Double] = []
    @Published var diskWriteHistory: [Double] = []
    @Published var diskFreeHistory: [Double] = []
    @Published var diskSmartStatus: String? = nil   // e.g. "Verified", "Not Supported", nil while loading
    @Published var diskWearInfo: NVMeWearInfo? = nil   // nil while loading or unavailable (external/older drives)
    @Published var gpuMetricsAvailable: Bool = false
    @Published var volumes: [VolumeInfo] = []

    /// Sleep and wake read from the system log, plus throttling this app saw
    /// happen, newest first. Only populated while the History window is open.
    @Published var systemEvents: [SystemEvent] = []

    @Published var thermalState: ProcessInfo.ThermalState = .nominal

    @Published var topCPUProcesses: [ProcessUsage] = []
    @Published var topMemoryProcesses: [ProcessUsage] = []
    @Published var topNetworkProcesses: [ProcessUsage] = []
    @Published var topDiskProcesses: [ProcessUsage] = []

    /// Ports this Mac is accepting connections on, and open connections per
    /// app. Only sampled while the Network window is visible.
    @Published var listeningPorts: [ListeningPort] = []
    @Published var connectionCounts: [ProcessUsage] = []

    @Published var localInterfaces: [LocalInterface] = []
    @Published var dnsServers: [String] = []
    @Published var isVPNActive: Bool = false
    @Published var vpnIsFortiClient: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionType: String = "Unknown"  // primary interface
    @Published var isLikelyHotspot: Bool = false
    @Published var isWifiAvailable: Bool = false
    @Published var isEthernetAvailable: Bool = false
    @Published var wifiSSID: String? = nil
    @Published var wifiRSSI: Int? = nil      // dBm, nil when not on WiFi

    @Published var publicIP: String?
    private var lastPublicIPFetchSuccess: Date?
    private var lastPublicIPFetchFailure: Date?
    private var publicIPFetchInFlight = false
    private var lastPathSignature: String?
    private var networkChangeDebounceTask: Task<Void, Never>?
    private var pathMonitor: NWPathMonitor?
    private var wifiMonitor: NWPathMonitor?
    private var ethernetMonitor: NWPathMonitor?

    @Published var pingLatencyMs: Double?
    @Published var pingHistory: [Double] = []
    private var pingTimer: Timer?

    @Published var batteryPercent: Int?
    @Published var batteryIsCharging: Bool = false
    @Published var batteryTimeRemainingMinutes: Int?
    @Published var powerSourceName: String = "Unknown"

    @Published var batteryCycleCount: Int?
    @Published var batteryDesignCycleCount: Int?
    @Published var batteryHealthPercent: Double?
    @Published var batteryTemperatureC: Double?
    @Published var batteryVoltage: Double?
    @Published var batteryAmperage: Int?
    @Published var batteryCondition: String = "Normal"

    @Published var displays: [DisplayInfo] = []
    @Published var bluetoothDevices: [BluetoothDevice] = []
    @Published var bluetoothAuthState: CBManagerAuthorization = CBCentralManager.authorization

    // SMC — temperatures and fans (read-only; fan writes require a root helper)
    @Published var cpuTemperatureC: Double?
    @Published var gpuTemperatureC: Double?
    @Published var fans: [FanInfo] = []
    @Published var extendedTemperatures: [TempReading] = []
    @Published var unknownSMCTemperatures: [TempReading] = []
    @Published var systemPowerWatts: Double?
    /// Only filled while the menu bar is showing watts; see `updateSMC`.
    @Published var powerHistory: [Double] = []

    // Per-domain power from IOReport's "Energy Model" group (Apple Silicon).
    // Nil when unavailable or while the Thermal window (the only consumer) is
    // hidden — sampling is gated on its visibility to keep idle cost at zero.
    @Published var cpuPowerWatts: Double?
    @Published var gpuPowerWatts: Double?
    @Published var anePowerWatts: Double?
    @Published var dramPowerWatts: Double?

    @Published var performanceCoreCount: Int = 0
    @Published var efficiencyCoreCount: Int = 0

    @Published var gpuName: String = "Unknown"
    @Published var gpuRecommendedMemoryGB: Double = 0
    @Published var gpuIsLowPower: Bool = false
    @Published var gpuIsRemovable: Bool = false
    var gpuLocation: String { gpuIsRemovable ? "External" : "Built-in" }
    @Published var gpuUsagePercent: Double = 0
    @Published var gpuHistory: [Double] = []

    let alerts = AlertService()

    /// User preferences (persistence + app appearance / activation policy).
    let settings = SettingsStore()
    /// On-disk history CSV persistence + export.
    let history = HistoryStore()
    /// On-disk daily network data-usage persistence (roadmap 1.2b).
    let dataUsage = DataUsageStore()
    /// Tiered SQLite history store (roadmap 1.3a, part 1 — recording only;
    /// the history-window UI that reads it lands separately). Lives
    /// alongside `history`; both are gated by the same
    /// `persistHistoryEnabled` preference.
    let historyDB = HistoryDatabase()
    private var historyCompactionTask: Task<Void, Never>?

    // MARK: - Per-domain samplers
    //
    // Each sampler owns its own delta/cache/throttle state and returns an
    // immutable snapshot; the engine is a thin coordinator that copies snapshots
    // onto the @Published properties above. See Sources/PerformanceApp/Samplers.
    private let cpuSampler: CPUSampling = CPUSampler()
    private let memorySampler: MemorySampling = MemorySampler()
    private let networkSampler: NetworkSampling = NetworkSampler()
    private let diskSampler: DiskSampling = DiskSampler()
    private let processSampler: ProcessSampling = ProcessSampler()
    private let networkProcessSampler: NetworkProcessSampling = NetworkProcessSampler()
    private let diskProcessSampler: DiskProcessSampling = DiskProcessSampler()
    private let batterySampler: BatterySampling = BatterySampler()
    private let wifiSampler: WiFiSampling = WiFiSampler()
    private let gpuSampler: GPUSampling = GPUSampler()
    private let smcSampler: SMCSampling = SMCSampler()
    private let snapshotWriter = SnapshotWriter()
    private let systemEventSampler: SystemEventSampling = SystemEventSampler()
    private let portSampler: PortSampling = PortSampler()
    private let powerSampler: PowerSampling = PowerSampler()
    private let bluetoothSampler = BluetoothSampler()

    enum Panel: String, CaseIterable, Identifiable, Codable, Transferable, PanelLayoutItem {
        case cpu        = "CPU"
        case memory     = "Memory"
        case disk       = "Disk"
        case thermal    = "Thermal"
        case gpu        = "GPU & Displays"
        case battery    = "Battery"
        case network    = "Network"
        case bluetooth  = "Bluetooth"
        var id: String { rawValue }
        var isFullWidth: Bool { self == .network || self == .bluetooth }

        var title: String {
            switch self {
            case .cpu:       return String(localized: "CPU")
            case .memory:    return String(localized: "Memory")
            case .disk:      return String(localized: "Disk")
            case .thermal:   return String(localized: "Thermal")
            case .gpu:       return String(localized: "GPU & Displays")
            case .battery:   return String(localized: "Battery")
            case .network:   return String(localized: "Network")
            case .bluetooth: return String(localized: "Bluetooth")
            }
        }

        var icon: String {
            switch self {
            case .cpu:       return "cpu"
            case .memory:    return "memorychip"
            case .disk:      return "internaldrive"
            case .thermal:   return "thermometer.medium"
            case .gpu:       return "cube.transparent"
            case .battery:   return "battery.75percent"
            case .network:   return "network"
            case .bluetooth: return "dot.radiowaves.left.and.right"
            }
        }

        var color: Color {
            switch self {
            case .cpu:       return MetricTheme.cpu
            case .memory:    return MetricTheme.memory
            case .disk:      return MetricTheme.disk
            case .thermal:   return .orange
            case .gpu:       return MetricTheme.gpu
            case .battery:   return MetricTheme.battery
            case .network:   return MetricTheme.networkDown
            case .bluetooth: return .blue
            }
        }

        static var transferRepresentation: some TransferRepresentation {
            ProxyRepresentation(exporting: \.rawValue) { Panel(rawValue: $0) ?? .cpu }
        }
    }

    typealias PanelRow = PerformanceAppCore.PanelRow<Panel>

    static func panelLayout(_ panels: [Panel]) -> [PanelRow] {
        PerformanceAppCore.PanelLayout.compute(panels)
    }

    enum PingServer: String, CaseIterable, Identifiable {
        case apple      = "apple"
        case cloudflare = "cloudflare"
        case google     = "google"
        case quad9      = "quad9"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .apple:      return String(localized: "Apple (default)")
            case .cloudflare: return String(localized: "Cloudflare (1.1.1.1)")
            case .google:     return String(localized: "Google (8.8.8.8)")
            case .quad9:      return String(localized: "Quad9 (9.9.9.9)")
            }
        }

        var urlString: String {
            switch self {
            case .apple:      return "https://captive.apple.com/hotspot-detect.html"
            case .cloudflare: return "https://one.one.one.one"
            case .google:     return "https://dns.google"
            case .quad9:      return "https://dns.quad9.net"
            }
        }
    }

    enum DiskDisplayMode: String, CaseIterable {
        case io    = "IO"
        case space = "Space"
    }

    private let historyLimit = 300 // ~5 min at 1s interval
    private func appendCapped(_ value: Double, to array: inout [Double]) {
        array.append(value)
        if array.count > historyLimit { array.removeFirst() }
    }
    private var extraBarController: ExtraMenuBarController?
    private var timer: Timer?
    private var thermalObserver: NSObjectProtocol?
    private var isRefreshing = false

    // MARK: - Panel visibility (drives process-list sampling cadence)
    //
    // The per-process samplers are costlier than the other samplers, so they
    // only run while a window that actually displays their output is visible:
    // the CPU and Memory detail windows show `topCPUProcesses`/
    // `topMemoryProcesses` (ps), the Network detail window shows
    // `topNetworkProcesses` (nettop), the Disk detail window shows
    // `topDiskProcesses` (a `proc_listpids` + `proc_pid_rusage` syscall loop —
    // no subprocess, so cheaper than the other two, but still a full sweep over
    // every live pid). The popover (OverviewView) doesn't display process lists
    // at all, so it isn't part of this gate. Nothing that feeds the menu bar
    // depends on these four published arrays, so MenuBarConfig-driven metrics
    // are unaffected and keep sampling every tick regardless of visibility.
    private var visiblePanels: Set<Panel> = []

    /// Called by `DetailWindow` (via `WindowFloatAccessor`) whenever one of its
    /// windows becomes visible or invisible (open/close, occlusion, miniaturize).
    /// Whether the popover is on screen. It shows Bluetooth devices, so the
    /// reads behind that are gated on it in the same way window panels are.
    private var popoverVisible = false

    /// True when something that shows Bluetooth devices is on screen.
    private var bluetoothIsOnScreen: Bool {
        popoverVisible || visiblePanels.contains(.bluetooth)
    }

    /// True when something shows the interface list, gateways or DNS servers.
    private var networkDetailIsOnScreen: Bool {
        popoverVisible || visiblePanels.contains(.network)
    }

    func setPopoverVisible(_ visible: Bool) {
        guard visible != popoverVisible else { return }
        popoverVisible = visible
        guard visible else { return }
        bluetoothSampler.resetThrottle()
        // The popover shows the local address and the VPN state, which are only
        // read while something displays them. Without this the first open would
        // show last session's values until the next tick.
        applyNetwork()
    }

    func setPanelVisible(_ visible: Bool, for kind: Panel) {
        let changed = visible ? visiblePanels.insert(kind).inserted : visiblePanels.remove(kind) != nil
        guard changed else { return }

        switch kind {
        case .cpu, .memory:
            if visible {
                processSampler.resetThrottle()
                updateProcesses()
            }
        case .network:
            if visible {
                applyNetwork()
                networkProcessSampler.resetThrottle()
                updateNetworkProcesses()
                portSampler.resetThrottle()
                updatePorts()
                // Latency is only ever displayed by the Network detail window,
                // so the probe only runs while that window is on screen.
                startPingTimer()
            } else {
                // Drop the rate baseline so the next visible sample starts
                // fresh instead of averaging over the whole invisible span.
                networkProcessSampler.invalidateBaseline()
                stopPingTimer()
            }
        case .disk:
            if visible {
                updateVolumes()
                diskProcessSampler.resetThrottle()
                updateDiskProcesses()
            } else {
                // Same reasoning as .network: drop the rate baseline so the next
                // visible sample starts fresh.
                diskProcessSampler.invalidateBaseline()
            }
        case .bluetooth:
            if visible { bluetoothSampler.resetThrottle() }
        case .thermal:
            // Only the Thermal window needs the full per-sensor set. Force an
            // immediate full read on open so it never shows a blank/stale grid
            // while waiting for the next tick.
            if visible {
                smcSampler.resetThrottle()
                updateSMC(forceExtended: true)
                powerSampler.resetThrottle()
                updatePower()
            } else {
                // Drop the per-domain readings so a reopened window starts fresh
                // and never briefly shows stale watts from a previous session.
                cpuPowerWatts = nil; gpuPowerWatts = nil
                anePowerWatts = nil; dramPowerWatts = nil
            }
        default:
            break
        }
    }

    /// Everything `SystemVerdict` needs, in one place.
    ///
    /// Both the popover banner and the Shortcuts action read this, so the two
    /// can never disagree about what the machine is doing.
    var verdictInput: SystemVerdict.Input {
        SystemVerdict.Input(
            cpuPercent: cpuUsagePercent,
            memoryUsedGB: memoryUsedGB,
            memoryTotalGB: memoryTotalGB,
            swapUsedGB: swapUsedGB,
            memoryPressureLevel: memoryPressureLevel,
            swapPagesPerSecond: swapPagesPerSecond,
            diskFreeGB: diskFreeGB,
            thermalLevel: Self.verdictThermalLevel(thermalState),
            // The process list is gated on a window being open, so most of the
            // time this is nil and the wording falls back to the unattributed
            // form rather than reaching for a fresh sample.
            topProcess: topCPUProcesses.first.map { ($0.name, $0.value) }
        )
    }

    static func verdictThermalLevel(_ state: ProcessInfo.ThermalState) -> Int {
        switch state {
        case .nominal:  return 0
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }

    /// Takes one process sample outside the usual visibility gating, for a
    /// Shortcuts action that needs a list no open window has produced.
    ///
    /// Deliberately a single sample rather than opening the gate: nothing is
    /// left running once the action has answered.
    func sampleProcessesOnce() async {
        processSampler.resetThrottle()
        guard let snapshot = await processSampler.sample(
            topCount: settings.topProcessCount,
            owners: GlossaryStore.shared.owners
        ) else { return }
        topCPUProcesses = snapshot.topCPU
        topMemoryProcesses = snapshot.topMemory
    }

    /// Loads sleep and wake events. Called when the History window opens; the
    /// sampler throttles the actual work to once every ten minutes.
    func refreshSystemEvents() async {
        guard let events = await systemEventSampler.sample() else { return }
        // Throttling this app watched happen is kept: it is not in any log, so
        // dropping it would lose the only record there is.
        let observed = systemEvents.filter { $0.kind == .throttling }
        systemEvents = (events + observed).sorted { $0.date > $1.date }
    }

    /// Records that throttling began. macOS keeps no log of this, so if the app
    /// does not write it down as it happens, nothing can show it later.
    private func recordThrottlingIfStarted(from previous: ProcessInfo.ThermalState) {
        let wasThrottling = Self.verdictThermalLevel(previous) >= 2
        let isThrottling = Self.verdictThermalLevel(thermalState) >= 2
        guard isThrottling, !wasThrottling else { return }
        systemEvents.insert(SystemEvent(kind: .throttling, date: Date()), at: 0)
    }

    func sparklineHistory(for metric: MenuBarMetric) -> [Double] {
        switch metric {
        case .cpu:     return Array(cpuHistory.suffix(30))
        case .memory:  return Array(memoryHistory.suffix(30))
        case .network: return Array((settings.networkSparklineUpload ? uploadHistory : downloadHistory).suffix(30))
        case .disk:    return Array((settings.diskSparklineWrite ? diskWriteHistory : diskReadHistory).suffix(30))
        case .gpu:     return Array(gpuHistory.suffix(30))
        case .power:   return Array(powerHistory.suffix(30))
        }
    }

    private func formatNetSpeed(_ kbps: Double) -> String {
        NetworkFormatting.formatSpeed(kbps: kbps)
    }

    func sparklineText(for metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu:     return String(format: "%.0f%%", cpuUsagePercent)
        case .memory:  return String(format: "%.1fG", memoryUsedGB)
        case .network: return formatNetSpeed(settings.networkSparklineUpload ? uploadSpeedKBps : downloadSpeedKBps)
        case .disk:    return String(format: "%.0fK", settings.diskSparklineWrite ? diskWriteKBps : diskReadKBps)
        case .gpu:     return String(format: "%.0f%%", gpuUsagePercent)
        case .power:   return systemPowerWatts.map { String(format: "%.0fW", $0) } ?? "—"
        }
    }

    func textOnlyLabel(for metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu:     return String(format: "CPU %.0f%%", cpuUsagePercent)
        case .memory:  return String(format: "MEM %.1fG", memoryUsedGB)
        case .network: return "↓\(formatNetSpeed(downloadSpeedKBps)) ↑\(formatNetSpeed(uploadSpeedKBps))"
        case .disk:    return settings.diskDisplayMode == .io
                           ? String(format: "R %.0fK W %.0fK", diskReadKBps, diskWriteKBps)
                           : String(format: "DSK %.1fG", diskFreeGB)
        case .gpu:     return String(format: "GPU %.0f%%", gpuUsagePercent)
        case .power:   return systemPowerWatts.map { String(format: "PWR %.0fW", $0) } ?? String(localized: "PWR n/a")
        }
    }

    /// Alert-threshold severity for a menu-bar metric, plus a short
    /// human-readable suffix for VoiceOver (nil when normal). Reuses the
    /// same threshold values as AlertService, so it stays in sync with the
    /// Alerts settings tab. A metric's threshold only counts as "applicable"
    /// when its alert type is enabled — if the user turned CPU alerting off,
    /// the CPU menu-bar item no longer treats its (still-stored) threshold
    /// as active. CPU/GPU/memory are usage-style (bad above the threshold);
    /// disk free space is headroom-style (bad below it), and only applies
    /// while the menu bar is showing free space rather than I/O throughput.
    /// Network has no configured alert threshold, so it is always `.normal`.
    func thresholdStatus(for metric: MenuBarMetric) -> (severity: ThresholdSeverity, label: String?) {
        func status(_ severity: ThresholdSeverity, _ direction: ThresholdSeverityMapper.Direction) -> (ThresholdSeverity, String?) {
            switch severity {
            case .normal:   return (.normal, nil)
            case .warning:  return (.warning, direction == .lowIsBad ? String(localized: "below alert threshold") : String(localized: "above alert threshold"))
            case .critical: return (.critical, direction == .lowIsBad ? String(localized: "well below alert threshold") : String(localized: "well above alert threshold"))
            }
        }
        switch metric {
        // No alert threshold is configured for watts, so it is never coloured,
        // the same as network.
        case .power:
            return (.normal, nil)
        case .cpu:
            let threshold = alerts.cpuEnabled ? alerts.cpuThreshold : nil
            let severity = ThresholdSeverityMapper.severity(value: cpuUsagePercent, threshold: threshold, direction: .highIsBad)
            return status(severity, .highIsBad)
        case .gpu:
            let threshold = alerts.gpuEnabled ? alerts.gpuThreshold : nil
            let severity = ThresholdSeverityMapper.severity(value: gpuUsagePercent, threshold: threshold, direction: .highIsBad)
            return status(severity, .highIsBad)
        case .memory:
            let pct = memoryTotalGB > 0 ? (memoryUsedGB / memoryTotalGB) * 100 : 0
            let threshold = (alerts.memoryEnabled && memoryTotalGB > 0) ? alerts.memoryThresholdPercent : nil
            let severity = ThresholdSeverityMapper.severity(value: pct, threshold: threshold, direction: .highIsBad)
            return status(severity, .highIsBad)
        case .disk:
            guard settings.diskDisplayMode == .space else { return (.normal, nil) }
            let threshold = alerts.diskEnabled ? alerts.diskFreeThresholdGB : nil
            let severity = ThresholdSeverityMapper.severity(value: diskFreeGB, threshold: threshold, direction: .lowIsBad)
            return status(severity, .lowIsBad)
        case .network:
            return (.normal, nil)
        }
    }

    init() {
        thermalState = ProcessInfo.processInfo.thermalState
        MetricsEngine.current = self
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let previous = self.thermalState
                self.thermalState = ProcessInfo.processInfo.thermalState
                self.recordThrottlingIfStarted(from: previous)
            }
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateDisplays() } }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateVolumes() } }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil, queue: .main
        ) { [weak self] _ in Task { @MainActor in self?.updateVolumes() } }
        // Preference side-effects that require engine action. SettingsStore has
        // already loaded persisted values in its own init; these fire only on
        // subsequent user changes (the load path is guarded).
        settings.onRefreshIntervalChanged = { [weak self] in self?.restartTimer() }
        settings.onPingServerChanged = { [weak self] in
            guard let self else { return }
            self.pingHistory = []
            // Only re-arm if someone is actually looking at the result.
            if self.visiblePanels.contains(.network) { self.startPingTimer() }
        }
        settings.onPublicIPEnabledChanged = { [weak self] enabled in
            if enabled { self?.fetchPublicIP() } else { self?.publicIP = nil }
        }
        alerts.loadPreferences()

        // Publish Bluetooth results as the sampler produces them.
        bluetoothSampler.onDevices = { [weak self] in self?.bluetoothDevices = $0 }
        bluetoothSampler.onAuth = { [weak self] in self?.bluetoothAuthState = $0 }

        updateGPUInfo()
        readCoreClusterCounts()
        updateDisplays()
        updateVolumes()
        startPathMonitor()
        // The ping timer is deliberately NOT started here — it only runs while
        // the Network detail window is visible. See `setPanelVisible`.
        if settings.publicIPEnabled { fetchPublicIP() }
        refresh()
        restartTimer()
        extraBarController = ExtraMenuBarController(engine: self, settings: settings)
        startHistoryCompactionLoop()
    }

    /// Opens the menu-bar popover (the live at-a-glance overview) from code —
    /// used by the onboarding tour to show the real popover. Returns `false`
    /// if there is no menu-bar status item to anchor it to.
    @discardableResult
    func showMenuBarPopover() -> Bool {
        extraBarController?.openPopover() ?? false
    }

    /// Runs `HistoryDatabase.compact()` about once a minute for the lifetime
    /// of the app. The `Task.detached` body hops onto `historyDB`'s own
    /// actor for the actual work, so compaction never runs on the main
    /// thread even though the loop is kicked off from here.
    private func startHistoryCompactionLoop() {
        historyCompactionTask = Task.detached(priority: .utility) { [historyDB] in
            while !Task.isCancelled {
                await historyDB.compact()
                try? await Task.sleep(nanoseconds: 60_000_000_000)
            }
        }
    }

    /// Fires a real HEAD request at an external host every 5 seconds, so it is
    /// started only while the Network detail window is visible — its only
    /// consumer — and stopped again when that window goes away. Left running
    /// unconditionally it was well over 700 needless requests an hour, waking
    /// the radio and draining battery for a number nobody was looking at.
    private func startPingTimer() {
        pingTimer?.invalidate()
        performLatencyCheck()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performLatencyCheck() }
        }
        // Let macOS coalesce this wakeup with others (latency needn't be
        // sampled on an exact 5s beat) — saves energy, especially on battery.
        pingTimer?.tolerance = 1
    }

    private func stopPingTimer() {
        pingTimer?.invalidate()
        pingTimer = nil
    }

    private func performLatencyCheck() {
        guard let url = URL(string: settings.pingServer.urlString) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 4
        request.cachePolicy = .reloadIgnoringLocalCacheData

        let start = Date()
        let task = URLSession.shared.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                guard let self else { return }
                if error == nil, response != nil {
                    let elapsedMs = Date().timeIntervalSince(start) * 1000
                    self.pingLatencyMs = elapsedMs
                    self.appendCapped(elapsedMs, to: &self.pingHistory)
                } else {
                    self.pingLatencyMs = nil
                }
            }
        }
        task.resume()
    }

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            // NWPathMonitor callbacks fire on `queue` below, not the main
            // thread — the signature comparison happens here (off-main) so
            // it captures every transient change, then the actual engine
            // updates hop to @MainActor.
            let signature = "\(path.status)|\(path.availableInterfaces.map(\.type).map(String.init(describing:)).sorted())"
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.connectionType = path.usesInterfaceType(.wifi) ? "Wi-Fi"
                    : path.usesInterfaceType(.wiredEthernet) ? "Ethernet"
                    : path.usesInterfaceType(.cellular) ? "Cellular"
                    : path.status == .satisfied ? "Other" : "Offline"
                self.isLikelyHotspot = NetworkClassification.isLikelyHotspot(
                    isExpensive: path.isExpensive,
                    usesWifi: path.usesInterfaceType(.wifi),
                    satisfied: path.status == .satisfied
                )

                let changed = self.lastPathSignature != nil && self.lastPathSignature != signature
                self.lastPathSignature = signature
                if changed, self.settings.publicIPEnabled {
                    // The old public IP belongs to the previous network path
                    // and is no longer trustworthy — clear it immediately.
                    // The actual fetch is debounced so a burst of transient
                    // updates during a handoff (Wi-Fi -> hotspot etc.)
                    // coalesces into a single request instead of one per
                    // intermediate path state.
                    self.publicIP = nil
                    self.networkChangeDebounceTask?.cancel()
                    self.networkChangeDebounceTask = Task { @MainActor [weak self] in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        guard !Task.isCancelled else { return }
                        self?.fetchPublicIP(networkChanged: true)
                    }
                }
            }
        }
        monitor.start(queue: DispatchQueue(label: "NetworkPathMonitor"))
        pathMonitor = monitor

        let wm = NWPathMonitor(requiredInterfaceType: .wifi)
        wm.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isWifiAvailable = path.status == .satisfied }
        }
        wm.start(queue: DispatchQueue(label: "WiFiMonitor"))
        wifiMonitor = wm

        let em = NWPathMonitor(requiredInterfaceType: .wiredEthernet)
        em.pathUpdateHandler = { [weak self] path in
            Task { @MainActor in self?.isEthernetAvailable = path.status == .satisfied }
        }
        em.start(queue: DispatchQueue(label: "EthernetMonitor"))
        ethernetMonitor = em
    }

    private func updateGPUInfo() {
        guard let info = gpuSampler.staticInfo() else { return }
        gpuName = info.name
        gpuRecommendedMemoryGB = info.recommendedMemoryGB
        gpuIsLowPower = info.isLowPower
        gpuIsRemovable = info.isRemovable
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: settings.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        // A ~15% tolerance lets the OS coalesce the refresh wakeup with other
        // timers instead of forcing a precise wakeup each interval. The
        // displayed cadence is unchanged; only the exact firing instant drifts.
        timer?.tolerance = settings.refreshInterval * 0.15
    }

    // MARK: - Refresh coordinator
    //
    // Preserves the original ordering and throttle cadence exactly: the
    // per-domain throttles (SMC 2s, Wi-Fi 3s, BT devices 5s, BT battery 25s,
    // battery health 60s, SMART 5min, public IP 5min) now live inside the
    // respective samplers. CPU/Memory/Disk/GPU/Battery now read off the main
    // thread (see the samplers' `Task.detached` reads); `refresh()` guards
    // against overlapping ticks the same way the individual samplers guard
    // against overlapping reads, so slow reads never let ticks stack up.
    func refresh() {
        guard !isRefreshing else { return }
        isRefreshing = true
        Task { @MainActor [weak self] in
            await self?.performRefresh()
            self?.isRefreshing = false
        }
    }

    private func performRefresh() async {
        await applyCPU()
        await applyMemory()
        applyNetwork()
        await applyDisk()
        updateProcesses()
        updateNetworkProcesses()
        updateDiskProcesses()
        updatePorts()
        await applyBattery()
        applyWiFi()
        bluetoothSampler.update(readDevices: bluetoothIsOnScreen)
        await applyGPU()
        updateSMC()
        updatePower()
        checkAlerts()
        checkWeeklyDigest()
        // Throttled to once every five seconds inside the writer, and a no-op
        // when the setting is off, so this costs a comparison on the tick.
        snapshotWriter.write(SnapshotWriter.Snapshot(engine: self),
                             enabled: settings.jsonSnapshotEnabled)
        history.append(enabled: settings.persistHistoryEnabled,
                       cpu: cpuUsagePercent,
                       memory: memoryUsedGB,
                       download: downloadSpeedKBps,
                       upload: uploadSpeedKBps,
                       diskFree: diskFreeGB)
        recordHistorySample()

        if settings.publicIPEnabled,
           PublicIPFetch.shouldFetch(lastSuccess: lastPublicIPFetchSuccess,
                                      lastFailure: lastPublicIPFetchFailure,
                                      now: Date(),
                                      networkChanged: false,
                                      inFlight: publicIPFetchInFlight) {
            fetchPublicIP()
        }
    }

    // MARK: - CPU

    private func applyCPU() async {
        guard let s = await cpuSampler.sample() else { return }
        cpuUsagePercent = s.usagePercent
        cpuUserPercent = s.userPercent
        cpuSystemPercent = s.systemPercent
        perCoreUsage = s.perCore
        loadAverages = s.loadAverages
        appendCapped(cpuUsagePercent, to: &cpuHistory)
    }

    // MARK: - Memory

    private func applyMemory() async {
        guard let s = await memorySampler.sample() else { return }
        memoryUsedGB = s.usedGB
        if memoryTotalGB != s.totalGB { memoryTotalGB = s.totalGB }
        memoryAppGB = s.appGB
        memoryWiredGB = s.wiredGB
        memoryCompressedGB = s.compressedGB
        if let swap = s.swapUsedGB { swapUsedGB = swap }
        memoryPressureLevel = s.pressureLevel
        swapPagesPerSecond = s.swapPagesPerSecond
        appendCapped(memoryUsedGB, to: &memoryHistory)
    }

    // MARK: - Network

    private func applyNetwork() {
        guard let s = networkSampler.sample(connectionType: connectionType, detailed: networkDetailIsOnScreen) else { return }
        downloadSpeedKBps = s.downloadKBps
        uploadSpeedKBps = s.uploadKBps
        // Assign only what moved. Every @Published write fires
        // objectWillChange whether or not the value changed, and most of what
        // is republished each tick is identical to last tick's: the interface
        // list, the DNS servers, the volumes, the battery's cycle count. With a
        // window open that also makes SwiftUI diff a list that did not change.
        if localInterfaces != s.interfaces { localInterfaces = s.interfaces }
        if dnsServers != s.dnsServers { dnsServers = s.dnsServers }
        if isVPNActive != s.isVPNActive { isVPNActive = s.isVPNActive }
        if vpnIsFortiClient != s.vpnIsFortiClient { vpnIsFortiClient = s.vpnIsFortiClient }
        appendCapped(downloadSpeedKBps, to: &downloadHistory)
        appendCapped(uploadSpeedKBps, to: &uploadHistory)
        dataUsage.record(physicalBytesReceived: s.physicalBytesReceived, physicalBytesSent: s.physicalBytesSent)
    }

    // MARK: - Disk

    private func applyDisk() async {
        guard let s = await diskSampler.sample() else { return }
        if diskTotalGB != s.totalGB { diskTotalGB = s.totalGB }
        diskFreeGB = s.freeGB
        guard let io = s.io else { return }
        diskReadKBps = io.readKBps
        diskWriteKBps = io.writeKBps
        if io.shouldFetchSMART {
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.diskSmartStatus = await self.diskSampler.fetchSMART()
                self.diskWearInfo = await self.diskSampler.fetchWear()
            }
        }
        appendCapped(diskReadKBps, to: &diskReadHistory)
        appendCapped(diskWriteKBps, to: &diskWriteHistory)
        appendCapped(diskFreeGB, to: &diskFreeHistory)
    }

    private func updateVolumes() {
        // Only the Disk window lists volumes, and enumerating them touches the
        // filesystem for every mount. Nothing else reads this.
        guard visiblePanels.contains(.disk) else { return }
        let currentVolumes = diskSampler.volumes()
        if volumes != currentVolumes { volumes = currentVolumes }
    }

    // MARK: - Top processes

    private func updateProcesses() {
        // ps is only sampled while the CPU or Memory detail window is open —
        // see `setPanelVisible`. The sampler itself throttles to a 3s cadence.
        guard visiblePanels.contains(.cpu) || visiblePanels.contains(.memory) else { return }
        let count = settings.topProcessCount
        Task { @MainActor [weak self] in
            guard let self, let snap = await self.processSampler.sample(topCount: count, owners: GlossaryStore.shared.owners) else { return }
            self.topCPUProcesses = snap.topCPU
            self.topMemoryProcesses = snap.topMemory
        }
    }

    // MARK: - Per-app network usage

    private func updateNetworkProcesses() {
        // nettop is only sampled while the Network detail window is open —
        // see `setPanelVisible`. The sampler itself throttles to a 3s cadence.
        guard visiblePanels.contains(.network) else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  let list = await self.networkProcessSampler.sample(topCount: self.settings.topProcessCount)
            else { return }
            self.topNetworkProcesses = list
        }
    }

    // MARK: - Per-app disk I/O

    private func updateDiskProcesses() {
        // proc_pid_rusage is only swept while the Disk detail window is open —
        // see `setPanelVisible`. The sampler itself throttles to a 3s cadence.
        guard visiblePanels.contains(.disk) else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  let list = await self.diskProcessSampler.sample(topCount: self.settings.topProcessCount)
            else { return }
            self.topDiskProcesses = list
        }
    }

    // MARK: - Process control

    func terminateProcess(pid: Int32) {
        kill(pid, SIGTERM)
    }

    // MARK: - Alerts

    private func checkAlerts() {
        alerts.check(cpu: cpuUsagePercent, memUsed: memoryUsedGB, memTotal: memoryTotalGB,
                     diskFree: diskFreeGB, gpu: gpuUsagePercent, thermal: thermalState)
    }

    // MARK: - Tiered SQLite history (roadmap 1.3a)

    /// Feeds the current tick's readings into `historyDB`, gated by the same
    /// `persistHistoryEnabled` preference as the CSV store. `HistoryDatabase`
    /// itself throttles to ~1 sample/second internally, so calling this every
    /// tick is safe even at a faster refresh interval.
    private func recordHistorySample() {
        guard settings.persistHistoryEnabled else { return }
        let memoryUsedPercent = memoryTotalGB > 0 ? (memoryUsedGB / memoryTotalGB) * 100 : 0
        let values: [HistoryMetric: Double] = [
            .cpuUsagePercent: cpuUsagePercent,
            .memoryUsedPercent: memoryUsedPercent,
            .gpuUsagePercent: gpuUsagePercent,
            .downloadSpeedKBps: downloadSpeedKBps,
            .uploadSpeedKBps: uploadSpeedKBps,
            .diskReadKBps: diskReadKBps,
            .diskWriteKBps: diskWriteKBps,
        ]
        let now = Date()
        Task { [historyDB] in await historyDB.record(values, at: now) }
    }

    // MARK: - History export

    /// Thin wrapper delegating to HistoryStore with the engine's in-memory
    /// ring buffers. Kept on the engine so existing call sites are unchanged.
    func exportHistoryCSV() {
        history.exportCSV(cpu: cpuHistory,
                          memory: memoryHistory,
                          download: downloadHistory,
                          upload: uploadHistory,
                          diskRead: diskReadHistory,
                          diskWrite: diskWriteHistory)
    }

    // MARK: - Battery / Power

    private func applyBattery() async {
        switch await batterySampler.sample() {
        case .noBattery:
            batteryPercent = nil
            powerSourceName = "No battery"
        case let .present(percent, isCharging, timeRemaining, powerSourceName, health):
            if batteryPercent != percent { batteryPercent = percent }
            if batteryIsCharging != isCharging { batteryIsCharging = isCharging }
            if batteryTimeRemainingMinutes != timeRemaining { batteryTimeRemainingMinutes = timeRemaining }
            if self.powerSourceName != powerSourceName { self.powerSourceName = powerSourceName }
            applyBatteryHealth(health)
        }
    }

    private func applyBatteryHealth(_ health: BatteryHealthSnapshot?) {
        guard let health else { return }
        switch health {
        case .unavailable:
            batteryCycleCount = nil
        case let .values(cycleCount, designCycleCount, healthPercent, temperatureC, voltage, amperage, condition):
            if batteryCycleCount != cycleCount { batteryCycleCount = cycleCount }
            if batteryDesignCycleCount != designCycleCount { batteryDesignCycleCount = designCycleCount }
            if batteryHealthPercent != healthPercent { batteryHealthPercent = healthPercent }
            if batteryAmperage != amperage { batteryAmperage = amperage }
            if let temperatureC { batteryTemperatureC = temperatureC }
            if let voltage { batteryVoltage = voltage }
            if let condition { batteryCondition = condition }
        }
    }

    // MARK: - Public IP (opt-in, calls a third-party service)

    /// - Parameter networkChanged: pass `true` when this fetch was triggered
    ///   by a detected network-path change, so the caller's own throttle
    ///   check can be skipped here too — the guard below still prevents a
    ///   second concurrent request via `publicIPFetchInFlight`.
    private func fetchPublicIP(networkChanged: Bool = false) {
        guard !publicIPFetchInFlight else { return }
        guard let url = URL(string: "https://api.ipify.org?format=text") else { return }
        publicIPFetchInFlight = true
        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            Task { @MainActor in
                guard let self else { return }
                self.publicIPFetchInFlight = false

                let httpStatus = (response as? HTTPURLResponse)?.statusCode
                guard error == nil, httpStatus == 200,
                      let data, let raw = String(data: data, encoding: .utf8),
                      PublicIPFetch.isPlausibleIPAddress(raw)
                else {
                    self.lastPublicIPFetchFailure = Date()
                    return
                }
                self.lastPublicIPFetchSuccess = Date()
                self.lastPublicIPFetchFailure = nil
                self.publicIP = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.resume()
    }

    // MARK: - Bluetooth

    func requestBluetoothAccess() {
        bluetoothSampler.requestAccess()
    }

    // MARK: - CPU Core Clusters

    private func readCoreClusterCounts() {
        var pCores: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("hw.perflevel0.physicalcpu", &pCores, &size, nil, 0)
        performanceCoreCount = Int(pCores)

        var eCores: Int32 = 0
        sysctlbyname("hw.perflevel1.physicalcpu", &eCores, &size, nil, 0)
        efficiencyCoreCount = Int(eCores)
    }

    // MARK: - WiFi Signal

    private func applyWiFi() {
        switch wifiSampler.sample(connectionType: connectionType) {
        case .clear:
            wifiSSID = nil
            wifiRSSI = nil
        case .throttled:
            break
        case let .value(ssid, rssi):
            if wifiSSID != ssid { wifiSSID = ssid }
            if wifiRSSI != rssi { wifiRSSI = rssi }
        }
    }

    // MARK: - GPU usage

    private func applyGPU() async {
        guard let usage = await gpuSampler.usage() else { return }
        gpuUsagePercent = usage
        appendCapped(gpuUsagePercent, to: &gpuHistory)
    }

    // MARK: - SMC (temperatures + fans)

    // The full per-sensor set (fans, extended/unknown temperatures, system
    // power) is only displayed by the Thermal detail window. When it isn't
    // visible we sample just the CPU/GPU averages the popover needs, and leave
    // the extended fields untouched — no wasted SMC reads and no @Published
    // churn on arrays nobody is observing. `forceExtended` covers the instant
    // the Thermal window opens, before the next scheduled tick.
    private func updateSMC(forceExtended: Bool = false) {
        let extended = forceExtended || visiblePanels.contains(.thermal)
        // One extra SMC key, and only for whoever put watts in their menu bar.
        let includePower = settings.isEnabled(.power)
        Task { @MainActor [weak self] in
            guard let self,
                  let s = await self.smcSampler.sample(extended: extended, includePower: includePower)
            else { return }
            self.cpuTemperatureC        = s.cpuTemperatureC
            self.gpuTemperatureC        = s.gpuTemperatureC
            if includePower || extended, let watts = s.systemPowerWatts {
                self.systemPowerWatts = watts
                self.appendCapped(watts, to: &self.powerHistory)
            }
            guard extended else { return }
            self.fans                   = s.fans
            self.extendedTemperatures   = s.extendedTemperatures
            self.unknownSMCTemperatures = s.unknownSMCTemperatures
            self.systemPowerWatts       = s.systemPowerWatts
        }
    }

    private func updatePorts() {
        guard visiblePanels.contains(.network) else { return }
        Task { @MainActor [weak self] in
            guard let self,
                  let snapshot = await self.portSampler.sample(owners: GlossaryStore.shared.owners)
            else { return }
            self.listeningPorts = snapshot.listening
            self.connectionCounts = snapshot.connections
        }
    }

    /// Sends a summary of last week, once on Monday morning.
    ///
    /// Asked on the tick rather than scheduled with a calendar trigger, because
    /// a Mac asleep at nine on Monday would miss the trigger entirely and one
    /// shut for a fortnight would be handed a backlog. See
    /// `WeeklyDigestSchedule`.
    private func checkWeeklyDigest() {
        guard settings.weeklyDigestEnabled,
              WeeklyDigestSchedule.isDue(now: Date(), lastSent: settings.weeklyDigestLastSent)
        else { return }
        // Claim the slot before the summary is built. Reading a week of history
        // is asynchronous, and without this a slow read would let the next tick
        // decide it is due as well.
        settings.weeklyDigestLastSent = Date()

        Task { @MainActor [weak self] in
            guard let self, let body = await self.weeklyDigestBody() else { return }
            self.alerts.post(title: String(localized: "Your week on this Mac"), body: body)
        }
    }

    /// One line per metric that has data, or nil when the week is empty, so a
    /// Mac that was off all week says nothing rather than reporting zeroes.
    private func weeklyDigestBody() async -> String? {
        let now = Date()
        let from = now.addingTimeInterval(-7 * 24 * 3600)
        var lines: [String] = []

        func aggregates(_ metric: HistoryMetric) async -> [HistoryAggregate] {
            await historyDB.samples(metric: metric, from: from, to: now)
                .map { HistoryAggregate(bucketStart: $0.date, min: $0.min, avg: $0.avg, max: $0.max) }
        }

        if let summary = WeeklySummary.metricSummary(await aggregates(.cpuUsagePercent)) {
            lines.append(String(format: String(localized: "CPU averaged %.0f%%, peaking at %.0f%%."),
                                summary.average, summary.peak))
        }
        if let summary = WeeklySummary.metricSummary(await aggregates(.memoryUsedPercent)) {
            lines.append(String(format: String(localized: "Memory averaged %.0f%%, peaking at %.0f%%."),
                                summary.average, summary.peak))
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    // MARK: - Per-domain power (IOReport Energy Model)

    // Only the Thermal detail window shows the per-domain watts, so — like the
    // extended SMC set — we sample only while it is visible. The sampler itself
    // throttles to a 2s cadence and needs one prior sample to form a delta, so
    // the first value appears ~2s after the window opens.
    private func updatePower() {
        guard visiblePanels.contains(.thermal) else { return }
        Task { @MainActor [weak self] in
            guard let self, let s = await self.powerSampler.sample() else { return }
            self.cpuPowerWatts  = s.cpuWatts
            self.gpuPowerWatts  = s.gpuWatts
            self.anePowerWatts  = s.aneWatts
            self.dramPowerWatts = s.dramWatts
        }
    }

    // MARK: - Displays

    private func updateDisplays() {
        let infos = NSScreen.screens.enumerated().map { index, screen in
            let scale = screen.backingScaleFactor
            let frame = screen.frame
            let nativeW = Int(frame.width * scale)
            let nativeH = Int(frame.height * scale)
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID ?? 0
            return DisplayInfo(
                id: index,
                name: screen.localizedName,
                width: nativeW,
                height: nativeH,
                refreshRateHz: screen.maximumFramesPerSecond,
                scaleFactor: scale,
                isMain: screen == NSScreen.main,
                isBuiltIn: CGDisplayIsBuiltin(screenID) != 0,
                colorProfile: screen.colorSpace?.localizedName ?? ""
            )
        }
        displays = infos

        Task.detached(priority: .utility) { [weak self] in
            guard let enriched = self?.enrichDisplaysFromSystemProfiler(base: infos) else { return }
            await MainActor.run { [weak self] in self?.displays = enriched }
        }
    }

    private nonisolated func enrichDisplaysFromSystemProfiler(base: [DisplayInfo]) -> [DisplayInfo] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        proc.arguments = ["SPDisplaysDataType", "-json"]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()
        guard (try? proc.run()) != nil else { return base }
        proc.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        guard
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let gpus = json["SPDisplaysDataType"] as? [[String: Any]]
        else { return base }

        // Flatten ndrvs from all GPU entries into a single list
        let ndrvs = gpus.flatMap { ($0["spdisplays_ndrvs"] as? [[String: Any]]) ?? [] }
        var result = base
        for (i, ndrv) in ndrvs.enumerated() {
            guard i < result.count else { break }
            let connRaw = ndrv["spdisplays_connection_type"] as? String ?? ""
            result[i].trueTone = (ndrv["spdisplays_ambient_brightness"] as? String) == "spdisplays_yes"
            result[i].connectionType = parseConnectionType(connRaw)
        }
        return result
    }

    private nonisolated func parseConnectionType(_ raw: String) -> String {
        if raw.contains("internal") || raw.contains("built") { return "Built-in" }
        if raw.contains("hdmi")                              { return "HDMI" }
        if raw.contains("thunderbolt")                       { return "Thunderbolt" }
        if raw.contains("displayport") || raw.contains("dp") { return "DisplayPort" }
        if raw.contains("usb")                              { return "USB-C" }
        return raw.isEmpty ? "" : raw
    }

}
