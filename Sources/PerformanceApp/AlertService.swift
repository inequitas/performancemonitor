import Foundation
import UserNotifications
import PerformanceAppCore

@MainActor
final class AlertService: ObservableObject {
    private let ud = UserDefaults.standard

    @Published var alertsEnabled: Bool = false {
        didSet { ud.set(alertsEnabled, forKey: "alertsEnabled"); if alertsEnabled { requestAuth() } }
    }
    @Published var cpuEnabled: Bool = true {
        didSet { ud.set(cpuEnabled, forKey: "cpuAlertEnabled") }
    }
    @Published var cpuThreshold: Double = 90 {
        didSet { ud.set(cpuThreshold, forKey: "cpuAlertThreshold") }
    }
    @Published var memoryEnabled: Bool = false {
        didSet { ud.set(memoryEnabled, forKey: "memoryAlertEnabled") }
    }
    @Published var memoryThresholdPercent: Double = 90 {
        didSet { ud.set(memoryThresholdPercent, forKey: "memoryAlertThresholdPct") }
    }
    @Published var diskEnabled: Bool = true {
        didSet { ud.set(diskEnabled, forKey: "diskAlertEnabled") }
    }
    @Published var diskFreeThresholdGB: Double = 10 {
        didSet { ud.set(diskFreeThresholdGB, forKey: "diskFreeAlertThresholdGB") }
    }
    @Published var gpuEnabled: Bool = false {
        didSet { ud.set(gpuEnabled, forKey: "gpuAlertEnabled") }
    }
    @Published var gpuThreshold: Double = 90 {
        didSet { ud.set(gpuThreshold, forKey: "gpuAlertThreshold") }
    }
    @Published var thermalEnabled: Bool = true {
        didSet { ud.set(thermalEnabled, forKey: "thermalAlertEnabled") }
    }
    /// How long (seconds) CPU/GPU/memory must stay continuously over their
    /// threshold before an alert fires. `0` fires on the very next tick,
    /// matching pre-dwell behaviour. Disk and thermal are intentionally not
    /// subject to this — disk free space is level-stable and thermal state
    /// is already debounced by macOS.
    @Published var alertSustainSeconds: Double = 30 {
        didSet { ud.set(alertSustainSeconds, forKey: "alertSustainSeconds") }
    }

    private var lastFired: [String: Date] = [:]
    private let cooldown: TimeInterval = 300
    private var dwellTracker = AlertDwellTracker()

    func loadPreferences() {
        func bool(_ k: String) -> Bool?   { ud.object(forKey: k) != nil ? ud.bool(forKey: k) : nil }
        func dbl(_ k: String)  -> Double? { ud.object(forKey: k) != nil ? ud.double(forKey: k) : nil }
        if let v = bool("alertsEnabled")            { alertsEnabled          = v }
        if let v = bool("cpuAlertEnabled")           { cpuEnabled             = v }
        if let v = bool("memoryAlertEnabled")        { memoryEnabled          = v }
        if let v = bool("diskAlertEnabled")          { diskEnabled            = v }
        if let v = bool("gpuAlertEnabled")           { gpuEnabled             = v }
        if let v = bool("thermalAlertEnabled")       { thermalEnabled         = v }
        if let v = dbl("cpuAlertThreshold")          { cpuThreshold           = v }
        if let v = dbl("memoryAlertThresholdPct")    { memoryThresholdPercent = v }
        if let v = dbl("diskFreeAlertThresholdGB")   { diskFreeThresholdGB    = v }
        if let v = dbl("gpuAlertThreshold")          { gpuThreshold           = v }
        if let v = dbl("alertSustainSeconds")        { alertSustainSeconds    = v }
    }

    func check(cpu: Double, memUsed: Double, memTotal: Double,
               diskFree: Double, gpu: Double, thermal: ProcessInfo.ThermalState) {
        guard alertsEnabled else { return }
        let now = Date()
        if cpuEnabled, dwellTracker.shouldFire(key: "cpu", isOver: cpu >= cpuThreshold, now: now, dwell: alertSustainSeconds) {
            fire("cpu", String(localized: "High CPU usage"),
                 String(format: String(localized: "CPU is at %.0f%%"), cpu), now: now)
        }
        if memoryEnabled, memTotal > 0 {
            let pct = (memUsed / memTotal) * 100
            if dwellTracker.shouldFire(key: "memory", isOver: pct >= memoryThresholdPercent, now: now, dwell: alertSustainSeconds) {
                fire("memory", String(localized: "High memory usage"),
                     String(format: String(localized: "%.1f / %.0f GB used (%.0f%%)"), memUsed, memTotal, pct), now: now)
            }
        }
        if diskEnabled, diskFree > 0, diskFree <= diskFreeThresholdGB {
            fire("disk", String(localized: "Low disk space"),
                 String(format: String(localized: "Only %.1f GB free"), diskFree), now: now)
        }
        if gpuEnabled, dwellTracker.shouldFire(key: "gpu", isOver: gpu >= gpuThreshold, now: now, dwell: alertSustainSeconds) {
            fire("gpu", String(localized: "High GPU usage"),
                 String(format: String(localized: "GPU is at %.0f%%"), gpu), now: now)
        }
        if thermalEnabled, thermal == .serious || thermal == .critical {
            fire("thermal", String(localized: "System running hot"),
                 String(format: String(localized: "Thermal pressure: %@"), thermal.label), now: now)
        }
    }

    private func fire(_ key: String, _ title: String, _ body: String, now: Date) {
        if let last = lastFired[key], now.timeIntervalSince(last) < cooldown { return }
        lastFired[key] = now
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        let req = UNNotificationRequest(identifier: "\(key)-\(now.timeIntervalSince1970)",
                                        content: content, trigger: nil)
        UNUserNotificationCenter.current().add(req)
    }

    private func requestAuth() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }
}
