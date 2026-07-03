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
    @Published var cpuIdlePercent: Double = 100
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
    @Published var gpuMetricsAvailable: Bool = false
    @Published var volumes: [VolumeInfo] = []

    @Published var thermalState: ProcessInfo.ThermalState = .nominal

    @Published var topCPUProcesses: [ProcessUsage] = []
    @Published var topMemoryProcesses: [ProcessUsage] = []
    @Published var topNetworkProcesses: [ProcessUsage] = []
    @Published var topDiskProcesses: [ProcessUsage] = []

    @Published var localInterfaces: [LocalInterface] = []
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
    @Published var gpuLocation: String = "Built-in"
    @Published var gpuUsagePercent: Double = 0
    @Published var gpuHistory: [Double] = []

    @Published var alertsEnabled: Bool = false {
        didSet {
            guard !isLoadingPreferences else { return }
            if alertsEnabled { requestNotificationAuthorization() }
            UserDefaults.standard.set(alertsEnabled, forKey: Pref.alertsEnabled)
        }
    }
    @Published var cpuAlertEnabled: Bool = true {
        didSet { UserDefaults.standard.set(cpuAlertEnabled, forKey: Pref.cpuAlertEnabled) }
    }
    @Published var cpuAlertThreshold: Double = 90 {
        didSet { UserDefaults.standard.set(cpuAlertThreshold, forKey: Pref.cpuAlertThreshold) }
    }
    @Published var memoryAlertEnabled: Bool = false {
        didSet { UserDefaults.standard.set(memoryAlertEnabled, forKey: Pref.memoryAlertEnabled) }
    }
    @Published var memoryAlertThresholdPercent: Double = 90 {
        didSet { UserDefaults.standard.set(memoryAlertThresholdPercent, forKey: Pref.memoryAlertThresholdPct) }
    }
    @Published var diskAlertEnabled: Bool = true {
        didSet { UserDefaults.standard.set(diskAlertEnabled, forKey: Pref.diskAlertEnabled) }
    }
    @Published var diskFreeAlertThresholdGB: Double = 10 {
        didSet { UserDefaults.standard.set(diskFreeAlertThresholdGB, forKey: Pref.diskFreeAlertThresholdGB) }
    }
    @Published var gpuAlertEnabled: Bool = false {
        didSet { UserDefaults.standard.set(gpuAlertEnabled, forKey: Pref.gpuAlertEnabled) }
    }
    @Published var gpuAlertThreshold: Double = 90 {
        didSet { UserDefaults.standard.set(gpuAlertThreshold, forKey: Pref.gpuAlertThreshold) }
    }
    @Published var thermalAlertEnabled: Bool = true {
        didSet { UserDefaults.standard.set(thermalAlertEnabled, forKey: Pref.thermalAlertEnabled) }
    }
    private var lastAlertFired: [String: Date] = [:]
    private let alertCooldown: TimeInterval = 300

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
        static var transferRepresentation: some TransferRepresentation {
            ProxyRepresentation(exporting: \.rawValue) { Panel(rawValue: $0) ?? .cpu }
        }
    }

    @Published var panelOrder: [Panel] = Panel.allCases {
        didSet { UserDefaults.standard.set(panelOrder.map(\.rawValue), forKey: Pref.panelOrder) }
    }
    @Published var hiddenPanels: Set<Panel> = [] {
        didSet { UserDefaults.standard.set(Array(hiddenPanels).map(\.rawValue), forKey: Pref.hiddenPanels) }
    }

    enum MenuBarMetric: String, CaseIterable, Identifiable {
        case cpu = "CPU"
        case memory = "Memory"
        case network = "Network"
        case disk = "Disk"
        var id: String { rawValue }
    }

    enum MenuBarStyle: String, CaseIterable, Identifiable {
        case sparkline = "Sparkline"
        case text      = "Text only"
        var id: String { rawValue }
    }

    @Published var menuBarMetric: MenuBarMetric = .cpu {
        didSet { UserDefaults.standard.set(menuBarMetric.rawValue, forKey: Pref.menuBarMetric) }
    }
    @Published var menuBarStyle: MenuBarStyle = .sparkline {
        didSet { UserDefaults.standard.set(menuBarStyle.rawValue, forKey: Pref.menuBarStyle) }
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

    var menuBarLabel: String {
        switch menuBarMetric {
        case .cpu: return String(format: "CPU %.0f%%", cpuUsagePercent)
        case .memory: return String(format: "MEM %.1fGB", memoryUsedGB)
        case .network: return String(format: "↓%.0f KB/s", downloadSpeedKBps)
        case .disk: return String(format: "DISK %.0fGB", diskFreeGB)
        }
    }

    @Published var menuBarImage: NSImage = NSImage()

    private var menuBarSparklineHistory: [Double] {
        let raw: [Double]
        switch menuBarMetric {
        case .cpu:     raw = cpuHistory
        case .memory:  raw = memoryHistory
        case .network: raw = downloadHistory
        case .disk:    raw = diskReadHistory
        }
        return Array(raw.suffix(30))
    }

    private var menuBarValueText: String {
        switch menuBarMetric {
        case .cpu:     return String(format: "%.0f%%", cpuUsagePercent)
        case .memory:  return String(format: "%.1fG", memoryUsedGB)
        case .network: return String(format: "%.0fK", downloadSpeedKBps)
        case .disk:    return String(format: "%.0fG", diskFreeGB)
        }
    }

    func renderMenuBarImage() {
        let valueText = menuBarValueText
        let h: CGFloat = 16

        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (valueText as NSString).size(withAttributes: attrs)

        switch menuBarStyle {
        case .text:
            let image = NSImage(size: NSSize(width: ceil(textSize.width), height: h), flipped: false) { _ in
                guard NSGraphicsContext.current != nil else { return false }
                (valueText as NSString).draw(
                    at: NSPoint(x: 0, y: (h - textSize.height) / 2),
                    withAttributes: attrs)
                return true
            }
            menuBarImage = image

        case .sparkline:
            let history = menuBarSparklineHistory
            let sparkW: CGFloat = 32
            let totalW = sparkW + 5 + ceil(textSize.width)

            let image = NSImage(size: NSSize(width: totalW, height: h), flipped: false) { _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }

                if history.count > 1 {
                    let peak = max(history.max() ?? 1, 0.001)
                    let step = sparkW / CGFloat(history.count - 1)

                    func point(_ i: Int) -> CGPoint {
                        CGPoint(x: CGFloat(i) * step,
                                y: 1 + CGFloat(history[i] / peak) * (h - 3))
                    }

                    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.setLineCap(.round)
                    ctx.setLineJoin(.round)
                    ctx.beginPath()
                    ctx.move(to: point(0))
                    for i in 1..<history.count { ctx.addLine(to: point(i)) }
                    ctx.strokePath()

                    ctx.beginPath()
                    ctx.move(to: point(0))
                    for i in 1..<history.count { ctx.addLine(to: point(i)) }
                    ctx.addLine(to: CGPoint(x: CGFloat(history.count - 1) * step, y: 0))
                    ctx.addLine(to: CGPoint(x: 0, y: 0))
                    ctx.closePath()
                    ctx.setFillColor(NSColor.white.withAlphaComponent(0.15).cgColor)
                    ctx.fillPath()
                }

                (valueText as NSString).draw(
                    at: NSPoint(x: sparkW + 5, y: (h - textSize.height) / 2),
                    withAttributes: attrs)
                return true
            }
            menuBarImage = image
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
    }

    private func startPingTimer() {
        pingTimer?.invalidate()
        performLatencyCheck()
        pingTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.performLatencyCheck() }
        }
    }

    private func performLatencyCheck() {
        guard let url = URL(string: "https://captive.apple.com/hotspot-detect.html") else { return }
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
                    self.pingHistory.append(elapsedMs)
                    if self.pingHistory.count > 60 { self.pingHistory.removeFirst() }
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
        gpuLocation = device.isRemovable ? "External" : "Built-in"
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
        renderMenuBarImage()
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
            cpuIdlePercent = max(100 - cpuUsagePercent, 0)
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
                var addr = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
                var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
                if inet_ntop(AF_INET, &addr, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil {
                    let ip = String(cString: buffer)
                    let isVPN = name.hasPrefix("utun") || name.hasPrefix("ppp") || name.hasPrefix("ipsec")
                    if isVPN { vpnDetected = true }
                    let wifiIfaceName = CWWiFiClient.shared().interface()?.interfaceName
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
                    if !isVPN {
                        interfaces.append(LocalInterface(name: name, address: ip, kind: kind))
                    }
                }
            }
            ptr = ifa.ifa_next
        }

        localInterfaces = interfaces
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
                        self.topNetworkProcesses = Array(list.sorted { $0.value > $1.value }.prefix(6))
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

    private func requestNotificationAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func checkAlerts() {
        guard alertsEnabled else { return }

        if cpuAlertEnabled, cpuUsagePercent >= cpuAlertThreshold {
            fireAlert(key: "cpu", title: "High CPU usage", body: String(format: "CPU is at %.0f%%", cpuUsagePercent))
        }
        if memoryAlertEnabled, memoryTotalGB > 0 {
            let memPct = (memoryUsedGB / memoryTotalGB) * 100
            if memPct >= memoryAlertThresholdPercent {
                fireAlert(key: "memory", title: "High memory usage", body: String(format: "%.1f / %.0f GB used (%.0f%%)", memoryUsedGB, memoryTotalGB, memPct))
            }
        }
        if diskAlertEnabled, diskFreeGB > 0, diskFreeGB <= diskFreeAlertThresholdGB {
            fireAlert(key: "disk", title: "Low disk space", body: String(format: "Only %.1f GB free", diskFreeGB))
        }
        if gpuAlertEnabled, gpuUsagePercent >= gpuAlertThreshold {
            fireAlert(key: "gpu", title: "High GPU usage", body: String(format: "GPU is at %.0f%%", gpuUsagePercent))
        }
        if thermalAlertEnabled, thermalState == .serious || thermalState == .critical {
            fireAlert(key: "thermal", title: "System running hot", body: "Thermal pressure: \(thermalState.label)")
        }
    }

    private func fireAlert(key: String, title: String, body: String) {
        let now = Date()
        if let last = lastAlertFired[key], now.timeIntervalSince(last) < alertCooldown { return }
        lastAlertFired[key] = now

        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        let request = UNNotificationRequest(identifier: "\(key)-\(now.timeIntervalSince1970)", content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
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
        static let alertsEnabled            = "alertsEnabled"
        static let cpuAlertEnabled          = "cpuAlertEnabled"
        static let cpuAlertThreshold        = "cpuAlertThreshold"
        static let memoryAlertEnabled       = "memoryAlertEnabled"
        static let memoryAlertThresholdPct  = "memoryAlertThresholdPct"
        static let diskAlertEnabled         = "diskAlertEnabled"
        static let diskFreeAlertThresholdGB = "diskFreeAlertThresholdGB"
        static let gpuAlertEnabled          = "gpuAlertEnabled"
        static let gpuAlertThreshold        = "gpuAlertThreshold"
        static let thermalAlertEnabled      = "thermalAlertEnabled"
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
        if let v = bool(Pref.alertsEnabled)             { alertsEnabled = v }
        if let v = bool(Pref.cpuAlertEnabled)           { cpuAlertEnabled = v }
        if let v = bool(Pref.memoryAlertEnabled)        { memoryAlertEnabled = v }
        if let v = bool(Pref.diskAlertEnabled)          { diskAlertEnabled = v }
        if let v = bool(Pref.gpuAlertEnabled)           { gpuAlertEnabled = v }
        if let v = bool(Pref.thermalAlertEnabled)       { thermalAlertEnabled = v }
        if let v = dbl(Pref.refreshInterval)            { refreshInterval = v }
        if let v = dbl(Pref.cpuAlertThreshold)         { cpuAlertThreshold = v }
        if let v = dbl(Pref.memoryAlertThresholdPct)   { memoryAlertThresholdPercent = v }
        if let v = dbl(Pref.diskFreeAlertThresholdGB)  { diskFreeAlertThresholdGB = v }
        if let v = dbl(Pref.gpuAlertThreshold)         { gpuAlertThreshold = v }
        if let v = int_(Pref.topProcessCount)           { topProcessCount = v }
        if let v = ud.string(forKey: Pref.menuBarMetric)  { menuBarMetric = MenuBarMetric(rawValue: v) ?? .cpu }
        if let v = ud.string(forKey: Pref.menuBarStyle)   { menuBarStyle = MenuBarStyle(rawValue: v) ?? .sparkline }

        if let raw = ud.stringArray(forKey: Pref.panelOrder) {
            let loaded = raw.compactMap { Panel(rawValue: $0) }
            let missing = Panel.allCases.filter { !loaded.contains($0) }
            panelOrder = loaded + missing
        }
        if let raw = ud.stringArray(forKey: Pref.hiddenPanels) {
            hiddenPanels = Set(raw.compactMap { Panel(rawValue: $0) })
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

        if Date().timeIntervalSince(batteryHealthCacheDate) > 60 {
            batteryHealthCacheDate = Date()
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
        guard Date().timeIntervalSince(btDevicesCacheDate) > 5 else { return }
        btDevicesCacheDate = Date()
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
        guard Date().timeIntervalSince(btBatteryCacheDate) > 25 else { return }
        // BLE GATT battery read (runs alongside system_profiler parse)
        let reader = BLEBatteryReader()
        bleBatteryReader = reader
        reader.onResult = { [weak self] name, pct in
            self?.bleBatteryByName[name] = pct
        }
        reader.read()
        btBatteryCacheDate = Date()
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
            await MainActor.run { self?.btBatteryCache = cache }
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
        guard Date().timeIntervalSince(wifiCacheDate) > 3 else { return }
        wifiCacheDate = Date()
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
        guard Date().timeIntervalSince(smcCacheDate) > 2 else { return }
        smcCacheDate = Date()
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
            let cpuSensors = known.filter { $0.category == "CPU" }
            let gpuSensors = known.filter { $0.category == "GPU" }
            let finalCpuT = cpuSensors.isEmpty ? cpuT
                : cpuSensors.map(\.celsius).reduce(0, +) / Double(cpuSensors.count)
            let finalGpuT = gpuSensors.isEmpty ? gpuT
                : gpuSensors.map(\.celsius).reduce(0, +) / Double(gpuSensors.count)
            await MainActor.run {
                self?.cpuTemperatureC          = finalCpuT
                self?.gpuTemperatureC          = finalGpuT
                self?.fans                     = f
                self?.extendedTemperatures     = known
                self?.unknownSMCTemperatures   = unknown
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
        displays = NSScreen.screens.enumerated().map { index, screen in
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
                isBuiltIn: CGDisplayIsBuiltin(screenID) != 0
            )
        }
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
