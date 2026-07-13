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

// Curated map of known Apple Silicon SMC temperature sensor keys → (friendly label, category).
// Keys absent from this map are silently dropped; this prevents unnamed/garbage sensors appearing in the UI.
// Covers M1 / M2 / M3 / M4 / M5 — keys that don't exist on a given chip are simply never discovered.
private let smcSensorLabels: [String: (String, String)] = [
    // ── CPU — M1 ──────────────────────────────────────────────────────────────
    "Tp09": ("CPU Efficiency Core 1",    "CPU"),  // M1 / M2 / M4
    "Tp0T": ("CPU Efficiency Core 2",    "CPU"),  // M1
    "Tp01": ("CPU Performance Core 1",   "CPU"),  // M1 / M2 / M4
    "Tp05": ("CPU Performance Core 2",   "CPU"),  // M1 / M2 / M4
    "Tp0D": ("CPU Performance Core 3",   "CPU"),  // M1 / M2
    "Tp0H": ("CPU Performance Core 4",   "CPU"),  // M1
    "Tp0L": ("CPU Performance Core 5",   "CPU"),  // M1
    "Tp0P": ("CPU Performance Core 6",   "CPU"),  // M1
    "Tp0X": ("CPU Performance Core 7",   "CPU"),  // M1 / M2
    "Tp0b": ("CPU Performance Core 8",   "CPU"),  // M1 / M2 / M4
    // ── CPU — M2 additional ───────────────────────────────────────────────────
    "Tp1h": ("CPU Efficiency Core 1",    "CPU"),
    "Tp1t": ("CPU Efficiency Core 2",    "CPU"),
    "Tp1p": ("CPU Efficiency Core 3",    "CPU"),
    "Tp1l": ("CPU Efficiency Core 4",    "CPU"),
    "Tp0f": ("CPU Performance Core 9",   "CPU"),
    "Tp0j": ("CPU Performance Core 10",  "CPU"),
    // ── CPU — M3 (Te*/Tf* prefix) ─────────────────────────────────────────────
    "Te05": ("CPU Efficiency Core 1",    "CPU"),  // M3 / M4
    "Te0L": ("CPU Efficiency Core 2",    "CPU"),  // M3
    "Te0P": ("CPU Efficiency Core 3",    "CPU"),  // M3
    "Te0S": ("CPU Efficiency Core 4",    "CPU"),  // M3 / M4
    "Te09": ("CPU Efficiency Core 3",    "CPU"),  // M4
    "Te0H": ("CPU Efficiency Core 4",    "CPU"),  // M4
    "Tf04": ("CPU Performance Core 1",   "CPU"),  // M3
    "Tf09": ("CPU Performance Core 2",   "CPU"),
    "Tf0A": ("CPU Performance Core 3",   "CPU"),
    "Tf0B": ("CPU Performance Core 4",   "CPU"),
    "Tf0D": ("CPU Performance Core 5",   "CPU"),
    "Tf0E": ("CPU Performance Core 6",   "CPU"),
    "Tf44": ("CPU Performance Core 7",   "CPU"),
    "Tf49": ("CPU Performance Core 8",   "CPU"),
    "Tf4A": ("CPU Performance Core 9",   "CPU"),
    "Tf4B": ("CPU Performance Core 10",  "CPU"),
    "Tf4D": ("CPU Performance Core 11",  "CPU"),
    "Tf4E": ("CPU Performance Core 12",  "CPU"),
    // ── CPU — M4 additional ───────────────────────────────────────────────────
    "Tp0V": ("CPU Performance Core 5",   "CPU"),
    "Tp0Y": ("CPU Performance Core 6",   "CPU"),
    "Tp0e": ("CPU Performance Core 8",   "CPU"),
    // ── GPU — M1 ──────────────────────────────────────────────────────────────
    "Tg05": ("GPU Cluster 1",            "GPU"),
    "Tg0D": ("GPU Cluster 2",            "GPU"),
    "Tg0L": ("GPU Cluster 3",            "GPU"),
    "Tg0T": ("GPU Cluster 4",            "GPU"),
    "Tg0b": ("GPU Cluster 5",            "GPU"),
    "Tg13": ("GPU Cluster 6",            "GPU"),
    "Tg1b": ("GPU Cluster 7",            "GPU"),
    "Tg23": ("GPU Cluster 8",            "GPU"),
    // ── GPU — M2 ──────────────────────────────────────────────────────────────
    "Tg0f": ("GPU Cluster 1",            "GPU"),
    "Tg0j": ("GPU Cluster 2",            "GPU"),
    // ── GPU — M3 (Tf* prefix) ─────────────────────────────────────────────────
    "Tf14": ("GPU Cluster 1",            "GPU"),
    "Tf18": ("GPU Cluster 2",            "GPU"),
    "Tf19": ("GPU Cluster 3",            "GPU"),
    "Tf1A": ("GPU Cluster 4",            "GPU"),
    "Tf24": ("GPU Cluster 5",            "GPU"),
    "Tf28": ("GPU Cluster 6",            "GPU"),
    "Tf29": ("GPU Cluster 7",            "GPU"),
    "Tf2A": ("GPU Cluster 8",            "GPU"),
    // ── GPU — M4 ──────────────────────────────────────────────────────────────
    "Tg0G": ("GPU Cluster 1",            "GPU"),
    "Tg0H": ("GPU Cluster 2",            "GPU"),
    "Tg1U": ("GPU Cluster 1",            "GPU"),
    "Tg1k": ("GPU Cluster 2",            "GPU"),
    "Tg0K": ("GPU Cluster 3",            "GPU"),
    "Tg0d": ("GPU Cluster 5",            "GPU"),
    "Tg0e": ("GPU Cluster 6",            "GPU"),
    "Tg0k": ("GPU Cluster 8",            "GPU"),
    // ── Trackpad — M1/M2 (single-sensor variants) ────────────────────────────
    "Ts0P": ("Trackpad",                 "Trackpad"),
    "Ts1P": ("Trackpad Actuator",        "Trackpad"),
    "Ts0S": ("Trackpad",                 "Trackpad"),
    "Ts1S": ("Trackpad Actuator",        "Trackpad"),
    // ── Trackpad haptic zones — M3/M4 (Force Touch actuator grid) ────────────
    "TD00": ("Zone A, Sensor 1",         "Trackpad"),
    "TD01": ("Zone A, Sensor 2",         "Trackpad"),
    "TD02": ("Zone A, Sensor 3",         "Trackpad"),
    "TD03": ("Zone A, Sensor 4",         "Trackpad"),
    "TD04": ("Zone A, Sensor 5",         "Trackpad"),
    "TD10": ("Zone B, Sensor 1",         "Trackpad"),
    "TD11": ("Zone B, Sensor 2",         "Trackpad"),
    "TD12": ("Zone B, Sensor 3",         "Trackpad"),
    "TD13": ("Zone B, Sensor 4",         "Trackpad"),
    "TD14": ("Zone B, Sensor 5",         "Trackpad"),
    "TD20": ("Zone C, Sensor 1",         "Trackpad"),
    "TD21": ("Zone C, Sensor 2",         "Trackpad"),
    "TD22": ("Zone C, Sensor 3",         "Trackpad"),
    "TD23": ("Zone C, Sensor 4",         "Trackpad"),
    "TD24": ("Zone C, Sensor 5",         "Trackpad"),
    "TDBP": ("Bottom Proximity",         "Trackpad"),
    "TDEL": ("Edge Left",                "Trackpad"),
    "TDER": ("Edge Right",               "Trackpad"),
    "TDTC": ("Center",                   "Trackpad"),
    "TDTP": ("Top Proximity",            "Trackpad"),
    // ── Storage ───────────────────────────────────────────────────────────────
    "TH0x": ("SSD",                      "Storage"),  // M-series NAND
    "TH0O": ("SSD",                      "Storage"),  // older variant
    "TH1O": ("SSD 2",                    "Storage"),
    "TH2O": ("SSD 3",                    "Storage"),
    "TH3O": ("SSD 4",                    "Storage"),
    // ── System / board ────────────────────────────────────────────────────────
    "TCHP": ("Charger Proximity",        "System"),
    "Ta0P": ("Airport Proximity",        "System"),
    "TW0P": ("WiFi Proximity",           "System"),
    "TPCD": ("Power Manager",            "System"),
    "TP0P": ("Power Supply",             "System"),
    "TaLP": ("Airflow Left",             "Airflow"),
    "TaRF": ("Airflow Right",            "Airflow"),
    // ── Memory ────────────────────────────────────────────────────────────────
    "Tm0P": ("Memory",                   "Memory"),
    "Tm02": ("Memory Module 1",          "Memory"),  // M1
    "Tm06": ("Memory Module 2",          "Memory"),
    "Tm08": ("Memory Module 3",          "Memory"),
    "Tm09": ("Memory Module 4",          "Memory"),
    "Tm0p": ("Memory Proximity 1",       "Memory"),  // M4
    "Tm1p": ("Memory Proximity 2",       "Memory"),
    "Tm2p": ("Memory Proximity 3",       "Memory"),
    // ── Battery (suppresses unknown display; not shown in UI) ─────────────────
    "TB0T": ("Battery",                  "Battery"),
    "TB1T": ("Battery 1",                "Battery"),
    "TB2T": ("Battery 2",                "Battery"),
]

@MainActor
final class MetricsEngine: ObservableObject {
    @Published var cpuUsagePercent: Double = 0
    @Published var cpuUserPercent: Double = 0
    @Published var cpuSystemPercent: Double = 0
    var cpuIdlePercent: Double { max(100 - cpuUsagePercent, 0) }
    @Published var loadAverages: (one: Double, five: Double, fifteen: Double) = (0, 0, 0)
    @Published var perCoreUsage: [Double] = []
    @Published var memoryUsedGB: Double = 0
    @Published var memoryTotalGB: Double = 0
    @Published var swapUsedGB: Double = 0
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
    @Published var gpuMetricsAvailable: Bool = false
    @Published var volumes: [VolumeInfo] = []

    @Published var thermalState: ProcessInfo.ThermalState = .nominal

    @Published var topCPUProcesses: [ProcessUsage] = []
    @Published var topMemoryProcesses: [ProcessUsage] = []
    @Published var topNetworkProcesses: [ProcessUsage] = []
    @Published var topDiskProcesses: [ProcessUsage] = []

    @Published var localInterfaces: [LocalInterface] = []
    @Published var dnsServers: [String] = []
    @Published var isVPNActive: Bool = false
    @Published var vpnIsFortiClient: Bool = false
    @Published var isConnected: Bool = false
    @Published var connectionType: String = "Unknown"  // primary interface
    @Published var isWifiAvailable: Bool = false
    @Published var isEthernetAvailable: Bool = false
    @Published var wifiSSID: String? = nil
    @Published var wifiRSSI: Int? = nil      // dBm, nil when not on WiFi

    @Published var publicIPEnabled: Bool = true {
        didSet {
            guard !isLoadingPreferences else { return }
            if publicIPEnabled { fetchPublicIP() } else { publicIP = nil }
            UserDefaults.standard.set(publicIPEnabled, forKey: Pref.publicIPEnabled)
        }
    }
    @Published var publicIP: String?
    private var lastPublicIPFetch: Date?
    private var pathMonitor: NWPathMonitor?
    private var wifiMonitor: NWPathMonitor?
    private var ethernetMonitor: NWPathMonitor?

    @Published var pingLatencyMs: Double?
    @Published var pingHistory: [Double] = []
    private var pingTimer: Timer?

    @Published var pingServer: PingServer = .apple {
        didSet {
            guard !isLoadingPreferences else { return }
            UserDefaults.standard.set(pingServer.rawValue, forKey: Pref.pingServer)
            pingHistory = []
            startPingTimer()
        }
    }

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
    private let smc = SMCReader()
    private var smcCacheDate: Date = .distantPast

    struct TempReading: Identifiable {
        var id: String { key }
        let key: String
        let label: String
        let category: String
        let celsius: Double
    }

    // Held strongly so the permission dialog can fire and the delegate callback arrives.
    private var btAuthManager: CBCentralManager?
    private var btDelegate: BluetoothAuthDelegate?
    private var btBatteryCache: [String: BtBatteryInfo] = [:]
    private var btBatteryCacheDate: Date = .distantPast
    private var bleBatteryByName: [String: Int] = [:]
    private var bleBatteryReader: BLEBatteryReader?
    private var wifiCacheDate: Date = .distantPast
    private var batteryHealthCacheDate: Date = .distantPast
    private var btDevicesCacheDate: Date = .distantPast
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

    @Published var showInDock: Bool = true {
        didSet {
            guard !isLoadingPreferences else { return }
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
            UserDefaults.standard.set(showInDock, forKey: Pref.showInDock)
        }
    }

    @Published var topProcessCount: Int = 6 {
        didSet { UserDefaults.standard.set(topProcessCount, forKey: Pref.topProcessCount) }
    }
    @Published var showRemovableVolumes: Bool = true {
        didSet { UserDefaults.standard.set(showRemovableVolumes, forKey: Pref.showRemovableVolumes) }
    }
    @Published var persistHistoryEnabled: Bool = false {
        didSet { UserDefaults.standard.set(persistHistoryEnabled, forKey: Pref.persistHistoryEnabled) }
    }
    private var isLoadingPreferences = false
    private let historyFileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerformanceApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("history.csv")
    }()
    private var historyFileHandle: FileHandle?

    enum Panel: String, CaseIterable, Identifiable, Codable, Transferable {
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
            case .gpu: return "GPU & Displays"
            default:   return rawValue
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

    struct PanelRow: Identifiable {
        var first:  Panel?
        var second: Panel?
        var full:   Panel?
        var id: String {
            [first?.id, second?.id, full?.id].compactMap { $0 }.joined(separator: "-")
        }
    }

    static func panelLayout(_ panels: [Panel]) -> [PanelRow] {
        var rows: [PanelRow] = []
        var pending: Panel?
        for panel in panels {
            if panel.isFullWidth {
                if let p = pending { rows.append(PanelRow(first: p)); pending = nil }
                rows.append(PanelRow(full: panel))
            } else {
                if let p = pending {
                    rows.append(PanelRow(first: p, second: panel)); pending = nil
                } else {
                    pending = panel
                }
            }
        }
        if let p = pending { rows.append(PanelRow(first: p)) }
        return rows
    }

    @Published var panelOrder: [Panel] = Panel.allCases {
        didSet { UserDefaults.standard.set(panelOrder.map(\.rawValue), forKey: Pref.panelOrder) }
    }
    @Published var hiddenPanels: Set<Panel> = [] {
        didSet { UserDefaults.standard.set(Array(hiddenPanels).map(\.rawValue), forKey: Pref.hiddenPanels) }
    }

    enum PingServer: String, CaseIterable, Identifiable {
        case apple      = "apple"
        case cloudflare = "cloudflare"
        case google     = "google"
        case quad9      = "quad9"

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .apple:      return "Apple (default)"
            case .cloudflare: return "Cloudflare (1.1.1.1)"
            case .google:     return "Google (8.8.8.8)"
            case .quad9:      return "Quad9 (9.9.9.9)"
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

    enum MenuBarMetric: String, CaseIterable, Identifiable, Codable, Transferable {
        case cpu = "CPU"
        case memory = "Memory"
        case network = "Network"
        case disk = "Disk"
        case gpu = "GPU"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .cpu:     return "cpu"
            case .memory:  return "memorychip"
            case .network: return "network"
            case .disk:    return "internaldrive"
            case .gpu:     return "rectangle.3.group"
            }
        }
        var color: Color {
            switch self {
            case .cpu:     return MetricTheme.cpu
            case .memory:  return MetricTheme.memory
            case .network: return MetricTheme.networkDown
            case .disk:    return MetricTheme.disk
            case .gpu:     return MetricTheme.gpu
            }
        }
        static var transferRepresentation: some TransferRepresentation {
            ProxyRepresentation(exporting: \.rawValue) { MenuBarMetric(rawValue: $0) ?? .cpu }
        }
    }

    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case sparkline = "Sparkline"
        case text      = "Text only"
        var id: String { rawValue }
    }

    enum DiskDisplayMode: String, CaseIterable {
        case io    = "IO"
        case space = "Space"
    }

    struct MenuBarConfig {
        var enabled: Bool
        var style: MenuBarStyle
    }

    // Single source of truth for all per-metric menu bar config.
    // CPU on/sparkline by default; all others off.
    @Published var menuBarConfig: [MenuBarMetric: MenuBarConfig] = {
        Dictionary(uniqueKeysWithValues: MenuBarMetric.allCases.map {
            ($0, MenuBarConfig(enabled: $0 == .cpu, style: .sparkline))
        })
    }()

    @Published var menuBarOrder: [MenuBarMetric] = MenuBarMetric.allCases {
        didSet { UserDefaults.standard.set(menuBarOrder.map(\.rawValue), forKey: "menuBarOrder") }
    }

    @Published var diskDisplayMode: DiskDisplayMode = .io {
        didSet { UserDefaults.standard.set(diskDisplayMode.rawValue, forKey: "diskDisplayMode") }
    }

    @Published var networkSparklineUpload: Bool = false {
        didSet { UserDefaults.standard.set(networkSparklineUpload, forKey: "networkSparklineUpload") }
    }

    @Published var diskSparklineWrite: Bool = false {
        didSet { UserDefaults.standard.set(diskSparklineWrite, forKey: "diskSparklineWrite") }
    }

    func isEnabled(_ metric: MenuBarMetric) -> Bool { menuBarConfig[metric]?.enabled ?? false }
    func styleFor(_ metric: MenuBarMetric) -> MenuBarStyle { menuBarConfig[metric]?.style ?? .sparkline }

    func setEnabled(_ enabled: Bool, for metric: MenuBarMetric) {
        menuBarConfig[metric, default: MenuBarConfig(enabled: false, style: .sparkline)].enabled = enabled
        UserDefaults.standard.set(enabled, forKey: "extraBar.\(metric.rawValue.lowercased())")
    }
    func setStyle(_ style: MenuBarStyle, for metric: MenuBarMetric) {
        menuBarConfig[metric, default: MenuBarConfig(enabled: false, style: .sparkline)].style = style
        UserDefaults.standard.set(style.rawValue, forKey: "extraStyle.\(metric.rawValue.lowercased())")
    }

    @Published var refreshInterval: Double = 1.0 {
        didSet {
            guard !isLoadingPreferences else { return }
            restartTimer()
            UserDefaults.standard.set(refreshInterval, forKey: Pref.refreshInterval)
        }
    }

    private let historyLimit = 300 // ~5 min at 1s interval
    private func appendCapped(_ value: Double, to array: inout [Double]) {
        array.append(value)
        if array.count > historyLimit { array.removeFirst() }
    }
    private let dynStore: SCDynamicStore? = SCDynamicStoreCreate(nil, "PerformanceApp" as CFString, nil, nil)
    private var extraBarController: ExtraMenuBarController?
    private var timer: Timer?
    private var previousCPUTicks: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
    private var previousNetBytes: (received: UInt64, sent: UInt64)?
    private var previousNetTimestamp: Date?
    private var previousDiskBytes: (read: UInt64, write: UInt64)?
    private var previousDiskTimestamp: Date?
    private var thermalObserver: NSObjectProtocol?
    private var processSamplerInFlight = false
    private var networkSamplerInFlight = false
    private var previousProcessNetBytes: [String: (in: Double, out: Double)] = [:]
    private var previousProcessNetTimestamp: Date?

    func sparklineHistory(for metric: MenuBarMetric) -> [Double] {
        switch metric {
        case .cpu:     return Array(cpuHistory.suffix(30))
        case .memory:  return Array(memoryHistory.suffix(30))
        case .network: return Array((networkSparklineUpload ? uploadHistory : downloadHistory).suffix(30))
        case .disk:    return Array((diskSparklineWrite ? diskWriteHistory : diskReadHistory).suffix(30))
        case .gpu:     return Array(gpuHistory.suffix(30))
        }
    }

    private func formatNetSpeed(_ kbps: Double) -> String {
        if kbps < 1000 { return String(format: "%.0fk", kbps) }
        let mbps = kbps / 1000
        if mbps < 1000 { return mbps < 10 ? String(format: "%.1fm", mbps) : String(format: "%.0fm", mbps) }
        let gbps = mbps / 1000
        return gbps < 10 ? String(format: "%.1fg", gbps) : String(format: "%.0fg", gbps)
    }

    func sparklineText(for metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu:     return String(format: "%.0f%%", cpuUsagePercent)
        case .memory:  return String(format: "%.1fG", memoryUsedGB)
        case .network: return formatNetSpeed(networkSparklineUpload ? uploadSpeedKBps : downloadSpeedKBps)
        case .disk:    return String(format: "%.0fK", diskSparklineWrite ? diskWriteKBps : diskReadKBps)
        case .gpu:     return String(format: "%.0f%%", gpuUsagePercent)
        }
    }

    func textOnlyLabel(for metric: MenuBarMetric) -> String {
        switch metric {
        case .cpu:     return String(format: "CPU %.0f%%", cpuUsagePercent)
        case .memory:  return String(format: "MEM %.1fG", memoryUsedGB)
        case .network: return "↓\(formatNetSpeed(downloadSpeedKBps)) ↑\(formatNetSpeed(uploadSpeedKBps))"
        case .disk:    return diskDisplayMode == .io
                           ? String(format: "R %.0fK W %.0fK", diskReadKBps, diskWriteKBps)
                           : String(format: "DSK %.1fG", diskFreeGB)
        case .gpu:     return String(format: "GPU %.0f%%", gpuUsagePercent)
        }
    }

    init() {
        thermalState = ProcessInfo.processInfo.thermalState
        thermalObserver = NotificationCenter.default.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.thermalState = ProcessInfo.processInfo.thermalState
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
        updateGPUInfo()
        readCoreClusterCounts()
        updateDisplays()
        updateVolumes()
        startPathMonitor()
        startPingTimer()
        loadPreferences()
        if publicIPEnabled { fetchPublicIP() }
        refresh()
        restartTimer()
        extraBarController = ExtraMenuBarController(engine: self)
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        performLatencyCheck()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performLatencyCheck() }
        }
    }

    private func performLatencyCheck() {
        guard let url = URL(string: pingServer.urlString) else { return }
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
            Task { @MainActor in
                guard let self else { return }
                self.isConnected = path.status == .satisfied
                self.connectionType = path.usesInterfaceType(.wifi) ? "Wi-Fi"
                    : path.usesInterfaceType(.wiredEthernet) ? "Ethernet"
                    : path.usesInterfaceType(.cellular) ? "Cellular"
                    : path.status == .satisfied ? "Other" : "Offline"
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
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        gpuName = device.name
        gpuRecommendedMemoryGB = Double(device.recommendedMaxWorkingSetSize) / 1_073_741_824
        gpuIsLowPower = device.isLowPower
        gpuIsRemovable = device.isRemovable
    }

    private func updateGPUUsage() {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault,
              IOServiceMatching("IOAccelerator"), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["PerformanceStatistics"] as? [String: Any] else { continue }

            // Apple Silicon: "GPU Core Utilization" is a Double in [0, 1]
            if let util = stats["GPU Core Utilization"] as? Double {
                gpuUsagePercent = util * 100
                appendCapped(gpuUsagePercent, to: &gpuHistory)
                return
            }
            // Fallback (discrete GPUs): "Device Utilization %" is an Int
            if let util = stats["Device Utilization %"] as? Int {
                gpuUsagePercent = Double(util)
                appendCapped(gpuUsagePercent, to: &gpuHistory)
                return
            }
        }
    }

    private func restartTimer() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        updateCPU()
        updateMemory()
        updateNetwork()
        updateDisk()
        updateProcesses()
        updateNetworkProcesses()
        updateBattery()
        updateWiFiSignal()
        updateBluetooth()
        updateGPUUsage()
        updateSMC()
        checkAlerts()
        appendPersistedHistoryRow()

        if publicIPEnabled, lastPublicIPFetch.map({ Date().timeIntervalSince($0) > 300 }) ?? true {
            fetchPublicIP()
        }
    }

    // MARK: - CPU

    private func updateCPU() {
        var numCPUsU: natural_t = 0
        var cpuInfo: processor_info_array_t!
        var numCPUInfo: mach_msg_type_number_t = 0

        let result = host_processor_info(mach_host_self(),
                                          PROCESSOR_CPU_LOAD_INFO,
                                          &numCPUsU,
                                          &cpuInfo,
                                          &numCPUInfo)
        guard result == KERN_SUCCESS else { return }

        let numCPUs = Int(numCPUsU)
        var ticksPerCore: [(user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)] = []
        let cpuLoadInfo = cpuInfo.withMemoryRebound(to: integer_t.self, capacity: Int(numCPUInfo)) { $0 }

        for i in 0..<numCPUs {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt32(cpuLoadInfo[base + Int(CPU_STATE_USER)])
            let system = UInt32(cpuLoadInfo[base + Int(CPU_STATE_SYSTEM)])
            let idle = UInt32(cpuLoadInfo[base + Int(CPU_STATE_IDLE)])
            let nice = UInt32(cpuLoadInfo[base + Int(CPU_STATE_NICE)])
            ticksPerCore.append((user, system, idle, nice))
        }

        vm_deallocate(mach_task_self_, vm_address_t(bitPattern: cpuInfo), vm_size_t(Int(numCPUInfo) * MemoryLayout<integer_t>.stride))

        if previousCPUTicks.count == ticksPerCore.count {
            var coreUsages: [Double] = []
            var totalUser: Double = 0
            var totalSystem: Double = 0
            var totalNice: Double = 0
            var totalTicks: Double = 0

            for i in 0..<ticksPerCore.count {
                let prev = previousCPUTicks[i]
                let curr = ticksPerCore[i]
                let userDelta = Double(curr.user &- prev.user)
                let systemDelta = Double(curr.system &- prev.system)
                let niceDelta = Double(curr.nice &- prev.nice)
                let idleDelta = Double(curr.idle &- prev.idle)
                let usedDelta = userDelta + systemDelta + niceDelta
                let total = usedDelta + idleDelta
                coreUsages.append(total > 0 ? (usedDelta / total) * 100 : 0)
                totalUser += userDelta
                totalSystem += systemDelta
                totalNice += niceDelta
                totalTicks += total
            }

            perCoreUsage = coreUsages
            cpuUsagePercent = totalTicks > 0 ? ((totalUser + totalSystem + totalNice) / totalTicks) * 100 : 0
            cpuUserPercent = totalTicks > 0 ? (totalUser / totalTicks) * 100 : 0
            cpuSystemPercent = totalTicks > 0 ? (totalSystem / totalTicks) * 100 : 0
        }

        previousCPUTicks = ticksPerCore

        var loadavg = [Double](repeating: 0, count: 3)
        if getloadavg(&loadavg, 3) == 3 {
            loadAverages = (loadavg[0], loadavg[1], loadavg[2])
        }
        appendCapped(cpuUsagePercent, to: &cpuHistory)
    }

    // MARK: - Memory

    private func updateMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
        let result = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return }

        let pageSize = Double(vm_kernel_page_size)
        let used = Double(stats.active_count + stats.inactive_count + stats.wire_count) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)

        memoryUsedGB = used / 1_073_741_824
        memoryTotalGB = total / 1_073_741_824
        memoryAppGB = Double(stats.active_count + stats.inactive_count) * pageSize / 1_073_741_824
        memoryWiredGB = Double(stats.wire_count) * pageSize / 1_073_741_824
        memoryCompressedGB = Double(stats.compressor_page_count) * pageSize / 1_073_741_824

        var swapUsage = xsw_usage()
        var size = MemoryLayout<xsw_usage>.stride
        if sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0) == 0 {
            swapUsedGB = Double(swapUsage.xsu_used) / 1_073_741_824
        }
        appendCapped(memoryUsedGB, to: &memoryHistory)
    }

    // MARK: - Network

    private func updateNetwork() {
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let firstAddr = ifaddrPtr else { return }
        defer { freeifaddrs(ifaddrPtr) }

        var totalReceived: UInt64 = 0
        var totalSent: UInt64 = 0
        var interfaces: [LocalInterface] = []
        var vpnDetected = false
        let wifiIfaceName = CWWiFiClient.shared().interface()?.interfaceName

        var ptr: UnsafeMutablePointer<ifaddrs>? = firstAddr
        while let current = ptr {
            let ifa = current.pointee
            let name = String(cString: ifa.ifa_name)
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_LINK), !name.hasPrefix("lo") {
                if let data = ifa.ifa_data {
                    let networkData = data.withMemoryRebound(to: if_data.self, capacity: 1) { $0.pointee }
                    totalReceived += UInt64(networkData.ifi_ibytes)
                    totalSent += UInt64(networkData.ifi_obytes)
                }
            }
            if let sa = ifa.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET), !name.hasPrefix("lo") {
                let addrIn = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
                var addr = addrIn.sin_addr
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: buffer)
                    let isVPN = name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec")
                    if isVPN { vpnDetected = true }
                    let kind: LocalInterface.Kind
                    if isVPN {
                        kind = .vpn
                    } else if name == wifiIfaceName {
                        kind = .wifi
                    } else if name.hasPrefix("en") || name.hasPrefix("bridge") {
                        kind = .ethernet
                    } else {
                        kind = .other
                    }
                    // Compute subnet prefix and network address from the netmask.
                    var prefix: Int? = nil
                    var netAddr: String? = nil
                    if let nm = ifa.ifa_netmask, nm.pointee.sa_family == UInt8(AF_INET) {
                        let maskBits = nm.withMemoryRebound(to: sockaddr_in.self, capacity: 1) {
                            UInt32(bigEndian: $0.pointee.sin_addr.s_addr)
                        }
                        prefix = maskBits.nonzeroBitCount
                        let net = UInt32(bigEndian: addrIn.sin_addr.s_addr) & maskBits
                        netAddr = "\(net >> 24).\((net >> 16) & 0xFF).\((net >> 8) & 0xFF).\(net & 0xFF)"
                    }
                    if !isVPN {
                        var gw: String? = nil
                        if let store = dynStore {
                            // Per-interface key (present when DHCP assigns the route)
                            if let dict = SCDynamicStoreCopyValue(store, "State:/Network/Interface/\(name)/IPv4" as CFString) as? [String: Any],
                               let router = dict["Router"] as? String, !router.contains(":") {
                                gw = router
                            }
                            // Fallback: global default gateway for the primary interface
                            if gw == nil,
                               let globalDict = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
                               (globalDict["PrimaryInterface"] as? String) == name,
                               let router = globalDict["Router"] as? String, !router.contains(":") {
                                gw = router
                            }
                        }
                        interfaces.append(LocalInterface(name: name, address: ip, kind: kind,
                                                         prefixLength: prefix, networkAddress: netAddr,
                                                         gateway: gw))
                    }
                }
            }
            ptr = ifa.ifa_next
        }

        // Mark the primary interface and sort it to the top
        let primaryKind: LocalInterface.Kind = connectionType == "Wi-Fi" ? .wifi : .ethernet
        localInterfaces = interfaces
            .map { iface in
                var i = iface; i.isPrimary = (i.kind == primaryKind); return i
            }
            .sorted { $0.isPrimary && !$1.isPrimary }
        isVPNActive = vpnDetected
        if vpnDetected {
            vpnIsFortiClient = NSWorkspace.shared.runningApplications.contains {
                let id = $0.bundleIdentifier?.lowercased() ?? ""
                let name = $0.localizedName?.lowercased() ?? ""
                return id.contains("fortinet") || id.contains("forticlient") || name.contains("forticlient")
            }
        } else {
            vpnIsFortiClient = false
        }

        let now = Date()
        if let prev = previousNetBytes, let prevTime = previousNetTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let receivedDelta = Double(totalReceived &- prev.received)
                let sentDelta = Double(totalSent &- prev.sent)
                downloadSpeedKBps = max(receivedDelta, 0) / elapsed / 1024
                uploadSpeedKBps = max(sentDelta, 0) / elapsed / 1024
            }
        }

        previousNetBytes = (totalReceived, totalSent)
        previousNetTimestamp = now
        appendCapped(downloadSpeedKBps, to: &downloadHistory)
        appendCapped(uploadSpeedKBps, to: &uploadHistory)

        // Read active DNS servers from the system dynamic store.
        if let store = dynStore,
           let dict = SCDynamicStoreCopyValue(store, "State:/Network/Global/DNS" as CFString) as? [String: Any],
           let servers = dict["ServerAddresses"] as? [String] {
            dnsServers = servers.filter { !$0.contains(":") }
        } else {
            dnsServers = []
        }
    }

    // MARK: - Disk

    private func updateDisk() {
        var fsStat = statfs()
        if statfs("/", &fsStat) == 0 {
            let blockSize = Double(fsStat.f_bsize)
            diskTotalGB = Double(fsStat.f_blocks) * blockSize / 1_073_741_824
            diskFreeGB = Double(fsStat.f_bavail) * blockSize / 1_073_741_824
        }

        var (totalRead, totalWrite): (UInt64, UInt64) = (0, 0)
        var iterator: io_iterator_t = 0
        let matching = IOServiceMatching("IOBlockStorageDriver")
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            defer {
                IOObjectRelease(service)
                service = IOIteratorNext(iterator)
            }
            var props: Unmanaged<CFMutableDictionary>?
            guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
                  let dict = props?.takeRetainedValue() as? [String: Any],
                  let stats = dict["Statistics"] as? [String: Any] else { continue }

            if let read = stats["Bytes (Read)"] as? UInt64 {
                totalRead += read
            }
            if let write = stats["Bytes (Write)"] as? UInt64 {
                totalWrite += write
            }
        }

        let now = Date()
        if let prev = previousDiskBytes, let prevTime = previousDiskTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                let readDelta = Double(totalRead &- prev.read)
                let writeDelta = Double(totalWrite &- prev.write)
                diskReadKBps = max(readDelta, 0) / elapsed / 1024
                diskWriteKBps = max(writeDelta, 0) / elapsed / 1024
            }
        }
        previousDiskBytes = (totalRead, totalWrite)
        previousDiskTimestamp = now
        appendCapped(diskReadKBps, to: &diskReadHistory)
        appendCapped(diskWriteKBps, to: &diskWriteHistory)
        appendCapped(diskFreeGB, to: &diskFreeHistory)
    }

    private func updateVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey, .volumeIsRemovableKey]
        guard let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) else {
            return
        }

        volumes = urls.compactMap { url -> VolumeInfo? in
            guard let values = try? url.resourceValues(forKeys: Set(keys)),
                  let total = values.volumeTotalCapacity,
                  let available = values.volumeAvailableCapacity else { return nil }
            let name = values.volumeName ?? url.lastPathComponent
            return VolumeInfo(
                name: name,
                totalGB: Double(total) / 1_073_741_824,
                freeGB: Double(available) / 1_073_741_824,
                isRemovable: values.volumeIsRemovable ?? false
            )
        }
    }

    // MARK: - Top processes

    private func updateProcesses() {
        guard !processSamplerInFlight else { return }
        processSamplerInFlight = true

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/ps")
        task.arguments = ["-arcwwwxo", "pid,comm,%cpu,%mem"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        let capturedCount = topProcessCount
        task.terminationHandler = { [weak self] _ in
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n").dropFirst()

            var cpuList: [ProcessUsage] = []
            var memList: [ProcessUsage] = []
            // ps %cpu is per-core: a process using 2 cores fully shows 200%.
            // Divide by logical CPU count to express as % of total system capacity.
            let logicalCPUs = Double(ProcessInfo.processInfo.processorCount).clamped(to: 1...256)

            for line in lines {
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 4,
                      let pid = Int32(parts[0]),
                      let rawCPU = Double(parts[parts.count - 2]),
                      let mem = Double(parts[parts.count - 1]) else { continue }
                let name = parts[1..<(parts.count - 2)].joined(separator: " ")
                let cpu = (rawCPU / logicalCPUs * 10).rounded() / 10
                cpuList.append(ProcessUsage(pid: pid, name: name, value: cpu))
                memList.append(ProcessUsage(pid: pid, name: name, value: mem))
            }

            let topCPU = Array(cpuList.sorted { $0.value > $1.value }.prefix(capturedCount))
            let topMem = Array(memList.sorted { $0.value > $1.value }.prefix(capturedCount))

            DispatchQueue.main.async {
                self?.topCPUProcesses = topCPU
                self?.topMemoryProcesses = topMem
                self?.processSamplerInFlight = false
            }
        }

        do {
            try task.run()
        } catch {
            processSamplerInFlight = false
        }
    }

    // MARK: - Per-app network usage

    private func updateNetworkProcesses() {
        guard !networkSamplerInFlight else { return }
        networkSamplerInFlight = true

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
        task.arguments = ["-P", "-x", "-L", "1", "-J", "bytes_in,bytes_out"]
        let outPipe = Pipe()
        task.standardOutput = outPipe
        task.standardError = Pipe()

        task.terminationHandler = { [weak self] _ in
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            let lines = output.split(separator: "\n").dropFirst()

            var current: [String: (in: Double, out: Double)] = [:]
            for line in lines {
                let parts = line.split(separator: ",", omittingEmptySubsequences: false)
                guard parts.count >= 3 else { continue }
                let name = String(parts[0])
                guard let bytesIn = Double(parts[1]), let bytesOut = Double(parts[2]) else { continue }
                current[name] = (bytesIn, bytesOut)
            }

            DispatchQueue.main.async {
                guard let self else { return }
                let now = Date()
                if let prevTime = self.previousProcessNetTimestamp {
                    let elapsed = now.timeIntervalSince(prevTime)
                    if elapsed > 0 {
                        var list: [ProcessUsage] = []
                        for (name, bytes) in current {
                            let prev = self.previousProcessNetBytes[name] ?? (0, 0)
                            let deltaIn = max(bytes.in - prev.in, 0)
                            let deltaOut = max(bytes.out - prev.out, 0)
                            let kbps = (deltaIn + deltaOut) / elapsed / 1024
                            if kbps > 0.05 {
                                let displayName = name.split(separator: ".").dropLast().joined(separator: ".")
                                list.append(ProcessUsage(pid: 0, name: displayName.isEmpty ? name : displayName, value: kbps))
                            }
                        }
                        self.topNetworkProcesses = Array(list.sorted { $0.value > $1.value }.prefix(self.topProcessCount))
                    }
                }
                self.previousProcessNetBytes = current
                self.previousProcessNetTimestamp = now
                self.networkSamplerInFlight = false
            }
        }

        do {
            try task.run()
        } catch {
            networkSamplerInFlight = false
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

    // MARK: - History persistence

    private func appendPersistedHistoryRow() {
        guard persistHistoryEnabled else { return }

        if historyFileHandle == nil {
            if !FileManager.default.fileExists(atPath: historyFileURL.path) {
                let header = "timestamp,cpu_percent,memory_gb,download_kbps,upload_kbps,disk_free_gb\n"
                try? header.write(to: historyFileURL, atomically: true, encoding: .utf8)
            }
            historyFileHandle = try? FileHandle(forWritingTo: historyFileURL)
            historyFileHandle?.seekToEndOfFile()
        }

        let row = "\(Date().timeIntervalSince1970),\(cpuUsagePercent),\(memoryUsedGB),\(downloadSpeedKBps),\(uploadSpeedKBps),\(diskFreeGB)\n"
        if let data = row.data(using: .utf8) {
            historyFileHandle?.write(data)
        }
    }

    // MARK: - Preferences persistence

    private enum Pref {
        static let showInDock               = "showInDock"
        static let refreshInterval          = "refreshInterval"
        static let topProcessCount          = "topProcessCount"
        static let showRemovableVolumes     = "showRemovableVolumes"
        static let persistHistoryEnabled    = "persistHistoryEnabled"
        static let publicIPEnabled          = "publicIPEnabled"
        static let menuBarMetric            = "menuBarMetric"
        static let menuBarStyle             = "menuBarStyle"
        static let panelOrder               = "panelOrder"
        static let hiddenPanels             = "hiddenPanels"
        static let pingServer               = "pingServer"
    }

    private func loadPreferences() {
        isLoadingPreferences = true
        defer {
            isLoadingPreferences = false
            NSApp.setActivationPolicy(showInDock ? .regular : .accessory)
        }
        let ud = UserDefaults.standard
        func bool(_ k: String) -> Bool?   { ud.object(forKey: k) != nil ? ud.bool(forKey: k) : nil }
        func dbl(_ k: String)  -> Double? { ud.object(forKey: k) != nil ? ud.double(forKey: k) : nil }
        func int_(_ k: String) -> Int?    { ud.object(forKey: k) != nil ? ud.integer(forKey: k) : nil }

        if let v = bool(Pref.showInDock)               { showInDock = v }
        if let v = bool(Pref.publicIPEnabled)           { publicIPEnabled = v }
        if let v = bool(Pref.showRemovableVolumes)      { showRemovableVolumes = v }
        if let v = bool(Pref.persistHistoryEnabled)     { persistHistoryEnabled = v }
        alerts.loadPreferences()
        if let v = dbl(Pref.refreshInterval)            { refreshInterval = v }
        if let v = int_(Pref.topProcessCount)           { topProcessCount = v }
        if let v = ud.string(forKey: Pref.pingServer)     { pingServer = PingServer(rawValue: v) ?? .apple }
        if let raw = ud.stringArray(forKey: "menuBarOrder") {
            let loaded = raw.compactMap { MenuBarMetric(rawValue: $0) }
            let missing = MenuBarMetric.allCases.filter { !loaded.contains($0) }
            menuBarOrder = loaded + missing
        }
        if let dm = DiskDisplayMode(rawValue: ud.string(forKey: "diskDisplayMode") ?? "") {
            diskDisplayMode = dm
        }
        networkSparklineUpload = ud.bool(forKey: "networkSparklineUpload")
        diskSparklineWrite     = ud.bool(forKey: "diskSparklineWrite")

        if let raw = ud.stringArray(forKey: Pref.panelOrder) {
            let loaded = raw.compactMap { Panel(rawValue: $0) }
            let missing = Panel.allCases.filter { !loaded.contains($0) }
            panelOrder = loaded + missing
        }
        if let raw = ud.stringArray(forKey: Pref.hiddenPanels) {
            hiddenPanels = Set(raw.compactMap { Panel(rawValue: $0) })
        }
        for metric in MenuBarMetric.allCases {
            let key = metric.rawValue.lowercased()
            let enabled = ud.object(forKey: "extraBar.\(key)") != nil ? ud.bool(forKey: "extraBar.\(key)") : (metric == .cpu)
            let style   = MenuBarStyle(rawValue: ud.string(forKey: "extraStyle.\(key)") ?? "") ?? .sparkline
            menuBarConfig[metric] = MenuBarConfig(enabled: enabled, style: style)
        }
    }

    func exportHistoryCSV() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "performance-history.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        var csv = "timestamp,cpu_percent,memory_gb,download_kbps,upload_kbps,disk_read_kbps,disk_write_kbps\n"
        let count = cpuHistory.count
        for i in 0..<count {
            let mem = i < memoryHistory.count ? memoryHistory[i] : 0
            let down = i < downloadHistory.count ? downloadHistory[i] : 0
            let up = i < uploadHistory.count ? uploadHistory[i] : 0
            let dr = i < diskReadHistory.count ? diskReadHistory[i] : 0
            let dw = i < diskWriteHistory.count ? diskWriteHistory[i] : 0
            csv += "\(i),\(cpuHistory[i]),\(mem),\(down),\(up),\(dr),\(dw)\n"
        }
        try? csv.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - Battery / Power

    private func updateBattery() {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            batteryPercent = nil
            powerSourceName = "No battery"
            return
        }

        batteryPercent = info[kIOPSCurrentCapacityKey] as? Int
        let state = info[kIOPSPowerSourceStateKey] as? String
        batteryIsCharging = (state == kIOPSACPowerValue)
        powerSourceName = batteryIsCharging ? "AC Power" : "Battery"

        if let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int, timeToEmpty >= 0, !batteryIsCharging {
            batteryTimeRemainingMinutes = timeToEmpty
        } else if let timeToFull = info[kIOPSTimeToFullChargeKey] as? Int, timeToFull >= 0, batteryIsCharging {
            batteryTimeRemainingMinutes = timeToFull
        } else {
            batteryTimeRemainingMinutes = nil
        }

        let now = Date()
        if now.timeIntervalSince(batteryHealthCacheDate) > 60 {
            batteryHealthCacheDate = now
            updateBatteryHealth()
        }
    }

    // MARK: - Public IP (opt-in, calls a third-party service)

    private func fetchPublicIP() {
        lastPublicIPFetch = Date()
        guard let url = URL(string: "https://api.ipify.org?format=text") else { return }
        URLSession.shared.dataTask(with: url) { [weak self] data, _, _ in
            guard let data, let ip = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in
                self?.publicIP = ip.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }.resume()
    }

    private func updateBatteryHealth() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            batteryCycleCount = nil
            return
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            batteryCycleCount = nil
            return
        }

        batteryCycleCount = props["CycleCount"] as? Int
        batteryDesignCycleCount = props["DesignCycleCount9C"] as? Int

        if let designCapacity = props["DesignCapacity"] as? Int, designCapacity > 0,
           let nominalCapacity = props["NominalChargeCapacity"] as? Int {
            batteryHealthPercent = (Double(nominalCapacity) / Double(designCapacity)) * 100
        } else {
            batteryHealthPercent = nil
        }

        if let temp = props["Temperature"] as? Int {
            batteryTemperatureC = Double(temp) / 100.0
        }
        if let voltage = props["Voltage"] as? Int {
            batteryVoltage = Double(voltage) / 1000.0
        }
        batteryAmperage = props["Amperage"] as? Int

        if let health = batteryHealthPercent {
            batteryCondition = health >= 80 ? "Normal" : "Service Recommended"
        }
    }

    // MARK: - Bluetooth

    func requestBluetoothAccess() {
        guard btDelegate == nil else { return }
        let delegate = BluetoothAuthDelegate { [weak self] auth in
            guard let self else { return }
            self.bluetoothAuthState = auth
            if auth == .allowedAlways {
                self.readBluetoothDevices()
            }
        }
        btDelegate = delegate
        btAuthManager = CBCentralManager(delegate: delegate, queue: .main)
    }

    private func updateBluetooth() {
        let auth = CBCentralManager.authorization
        bluetoothAuthState = auth
        switch auth {
        case .allowedAlways:
            // Ensure CBCentralManager exists — needed for BLE disconnect.
            // If already authorised at launch, requestBluetoothAccess() is never
            // called by the notDetermined path, leaving btAuthManager nil.
            if btAuthManager == nil { requestBluetoothAccess() }
            readBluetoothDevices()
        case .notDetermined:
            requestBluetoothAccess()
        default:
            break
        }
    }

    private func readBluetoothDevices() {
        refreshBTBatteryCache()
        let now = Date()
        guard now.timeIntervalSince(btDevicesCacheDate) > 5 else { return }
        btDevicesCacheDate = now
        guard let paired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else { return }
        bluetoothDevices = paired.map { device in
            let cod = device.classOfDevice
            let majorClass = (Int(cod) & 0x1F00) >> 8
            let icon: String
            switch majorClass {
            case 1: icon = "laptopcomputer"
            case 2: icon = "iphone"
            case 4: icon = "headphones"
            case 5: icon = "keyboard"
            default: icon = "dot.radiowaves.left.and.right"
            }
            let addr = (device.addressString ?? "").lowercased().replacingOccurrences(of: "-", with: ":")
            let name = device.nameOrAddress ?? "Unknown"
            let info = btBatteryCache[addr]
            let earbud: Int? = info.flatMap { i in [i.left, i.right].compactMap { $0 }.min() }
            let primary: Int? = info?.main ?? earbud ?? bleBatteryByName[name]
            return BluetoothDevice(
                id: device.addressString ?? UUID().uuidString,
                name: name,
                isConnected: device.isConnected(),
                batteryPercent: primary,
                batteryLeft: info?.left,
                batteryRight: info?.right,
                batteryCase: info?.caseLevel,
                icon: icon
            )
        }
    }

    private struct BtBatteryInfo {
        var main: Int?
        var left: Int?
        var right: Int?
        var caseLevel: Int?
    }

    private func refreshBTBatteryCache() {
        let now = Date()
        guard now.timeIntervalSince(btBatteryCacheDate) > 25 else { return }
        btBatteryCacheDate = now
        // BLE GATT battery read (runs alongside system_profiler parse)
        let reader = BLEBatteryReader()
        bleBatteryReader = reader
        reader.onResult = { [weak self] name, pct in
            self?.bleBatteryByName[name] = pct
        }
        reader.read()
        Task.detached(priority: .utility) { [weak self] in
            let proc = Process()
            proc.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            proc.arguments = ["SPBluetoothDataType", "-json"]
            let pipe = Pipe()
            proc.standardOutput = pipe
            proc.standardError = Pipe()
            guard (try? proc.run()) != nil else { return }
            proc.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let btArray = json["SPBluetoothDataType"] as? [[String: Any]] else { return }

            func parsePct(_ info: [String: Any], _ key: String) -> Int? {
                guard let s = info[key] as? String else { return nil }
                return Int(s.replacingOccurrences(of: "%", with: "").trimmingCharacters(in: .whitespaces))
            }

            var cache: [String: BtBatteryInfo] = [:]
            for entry in btArray {
                for listKey in ["device_connected", "device_not_connected"] {
                    guard let deviceList = entry[listKey] as? [[String: Any]] else { continue }
                    for deviceDict in deviceList {
                        for (_, infoAny) in deviceDict {
                            guard let info = infoAny as? [String: Any],
                                  let addr = info["device_address"] as? String else { continue }
                            let norm = addr.lowercased().replacingOccurrences(of: "-", with: ":")
                            cache[norm] = BtBatteryInfo(
                                main:      parsePct(info, "device_batteryLevel"),
                                left:      parsePct(info, "device_batteryLevelLeft"),
                                right:     parsePct(info, "device_batteryLevelRight"),
                                caseLevel: parsePct(info, "device_batteryLevelCase")
                            )
                        }
                    }
                }
            }
            let captured = cache
            await MainActor.run { [weak self] in self?.btBatteryCache = captured }
        }
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

    private func updateWiFiSignal() {
        guard connectionType == "Wi-Fi" else {
            wifiSSID = nil
            wifiRSSI = nil
            wifiCacheDate = .distantPast
            return
        }
        let now = Date()
        guard now.timeIntervalSince(wifiCacheDate) > 3 else { return }
        wifiCacheDate = now
        let iface = CWWiFiClient.shared().interface()
        wifiSSID = iface?.ssid()
        if let rssi = iface?.rssiValue(), rssi != 0 {
            wifiRSSI = rssi
        } else {
            wifiRSSI = nil
        }
    }

    // MARK: - SMC (temperatures + fans)

    private func updateSMC() {
        guard smc.isOpen else { return }
        let now = Date()
        guard now.timeIntervalSince(smcCacheDate) > 2 else { return }
        smcCacheDate = now
        let reader = smc  // capture before leaving @MainActor; SMCReader is @unchecked Sendable
        Task.detached(priority: .utility) { [weak self] in
            let cpuT     = reader.cpuTemperature()
            let gpuT     = reader.gpuTemperature()
            let f        = reader.fans()
            let allTemps = reader.readAllTemperatures()
            var known: [TempReading] = []
            var unknown: [TempReading] = []
            for (key, value) in allTemps {
                if let (label, category) = MetricsEngine.categorize(key: key) {
                    known.append(TempReading(key: key, label: label, category: category, celsius: value))
                } else {
                    unknown.append(TempReading(key: key, label: key, category: "Unknown", celsius: value))
                }
            }
            // Derive CPU/GPU averages from extended sensors when available.
            // This handles M3/M4 which use Te*/Tf* keys that cpuTemperature()/gpuTemperature()
            // won't find (those only look for Tp*/Tg* prefixes).
            var cpuSensors: [TempReading] = []
            var gpuSensors: [TempReading] = []
            for r in known {
                if r.category == "CPU" { cpuSensors.append(r) }
                else if r.category == "GPU" { gpuSensors.append(r) }
            }
            let finalCpuT = cpuSensors.isEmpty ? cpuT
                : cpuSensors.map(\.celsius).reduce(0, +) / Double(cpuSensors.count)
            let finalGpuT = gpuSensors.isEmpty ? gpuT
                : gpuSensors.map(\.celsius).reduce(0, +) / Double(gpuSensors.count)
            let finalCpu = finalCpuT, finalGpu = finalGpuT, finalFans = f, finalExt = known, finalUnk = unknown
            await MainActor.run { [weak self] in
                self?.cpuTemperatureC        = finalCpu
                self?.gpuTemperatureC        = finalGpu
                self?.fans                   = finalFans
                self?.extendedTemperatures   = finalExt
                self?.unknownSMCTemperatures = finalUnk
            }
        }
    }

    // Returns nil for any key not in the curated map — prevents surfacing unnamed sensors.
    private nonisolated static func categorize(key: String) -> (label: String, category: String)? {
        guard let (label, category) = smcSensorLabels[key] else { return nil }
        return (label: label, category: category)
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

struct DisplayInfo: Identifiable {
    let id: Int
    let name: String
    let width: Int
    let height: Int
    let refreshRateHz: Int
    let scaleFactor: Double
    let isMain: Bool
    let isBuiltIn: Bool
    var colorProfile: String = ""
    var trueTone: Bool = false
    var connectionType: String = ""
}


struct VolumeInfo: Identifiable {
    let name: String
    let totalGB: Double
    let freeGB: Double
    let isRemovable: Bool
    var id: String { name }
}

struct LocalInterface: Identifiable {
    enum Kind { case wifi, ethernet, vpn, other }
    let name: String
    let address: String
    let kind: Kind
    var isPrimary: Bool = false
    var prefixLength: Int? = nil
    var networkAddress: String? = nil
    var gateway: String? = nil
    var subnetMask: String? {
        guard let p = prefixLength, p > 0 else { return nil }
        let bits = p >= 32 ? UInt32.max : ~(UInt32.max >> p)
        return "\(bits >> 24).\((bits >> 16) & 0xFF).\((bits >> 8) & 0xFF).\(bits & 0xFF)"
    }
    var id: String { name }

    var icon: String {
        switch kind {
        case .wifi:     return "wifi"
        case .ethernet: return "cable.connector"
        case .vpn:      return "lock.shield.fill"
        case .other:    return "network"
        }
    }

    var displayName: String {
        switch kind {
        case .wifi:     return "Wi-Fi"
        case .ethernet: return "Ethernet"
        case .vpn:      return "VPN"
        case .other:    return name
        }
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

struct ProcessUsage: Identifiable {
    let pid: Int32
    let name: String
    let value: Double
    var id: String { "\(pid)-\(name)" }
}

struct BluetoothDevice: Identifiable {
    let id: String
    let name: String
    let isConnected: Bool
    let batteryPercent: Int?    // primary / overall; for earbuds = min(L, R)
    let batteryLeft: Int?       // AirPods left earbud
    let batteryRight: Int?      // AirPods right earbud
    let batteryCase: Int?       // AirPods case
    let icon: String
}

// NSObject subclass required for CBCentralManagerDelegate conformance.
final class BluetoothAuthDelegate: NSObject, CBCentralManagerDelegate {
    private let onUpdate: (CBManagerAuthorization) -> Void

    init(onUpdate: @escaping (CBManagerAuthorization) -> Void) {
        self.onUpdate = onUpdate
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        onUpdate(CBCentralManager.authorization)
    }
}

// Reads GATT Battery Service (0x180F) from BLE peripherals already connected to the system.
final class BLEBatteryReader: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    private static let batterySvc  = CBUUID(string: "180F")
    private static let batteryChar = CBUUID(string: "2A19")

    private var central: CBCentralManager?
    private var inFlight: Set<CBPeripheral> = []
    var onResult: ((String, Int) -> Void)?   // peripheral.name → percent

    func read() {
        // Re-create central each time so state machine resets cleanly
        central = CBCentralManager(delegate: self, queue: .main,
                                   options: [CBCentralManagerOptionShowPowerAlertKey: false])
    }

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        guard central.state == .poweredOn else { return }
        let peripherals = central.retrieveConnectedPeripherals(withServices: [Self.batterySvc])
        for p in peripherals {
            p.delegate = self
            inFlight.insert(p)
            central.connect(p, options: nil)
        }
    }

    func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        peripheral.discoverServices([Self.batterySvc])
    }

    func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        inFlight.remove(peripheral)
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { inFlight.remove(peripheral); return }
        for svc in services where svc.uuid == Self.batterySvc {
            peripheral.discoverCharacteristics([Self.batteryChar], for: svc)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        guard let chars = service.characteristics else { inFlight.remove(peripheral); return }
        for c in chars where c.uuid == Self.batteryChar {
            peripheral.readValue(for: c)
        }
    }

    func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        defer { inFlight.remove(peripheral); central?.cancelPeripheralConnection(peripheral) }
        guard characteristic.uuid == Self.batteryChar,
              let data = characteristic.value, let raw = data.first,
              let name = peripheral.name else { return }
        let pct = Int(raw)
        guard pct >= 0, pct <= 100 else { return }
        onResult?(name, pct)
    }
}
