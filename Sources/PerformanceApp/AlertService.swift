import Foundation
import UserNotifications

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

    private var lastFired: [String: Date] = [:]
    private let cooldown: TimeInterval = 300

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
    }

    func check(cpu: Double, memUsed: Double, memTotal: Double,
               diskFree: Double, gpu: Double, thermal: ProcessInfo.ThermalState) {
        guard alertsEnabled else { return }
        if cpuEnabled, cpu >= cpuThreshold {
            fire("cpu", "High CPU usage", String(format: "CPU is at %.0f%%", cpu))
        }
        if memoryEnabled, memTotal > 0 {
            let pct = (memUsed / memTotal) * 100
            if pct >= memoryThresholdPercent {
                fire("memory", "High memory usage",
                     String(format: "%.1f / %.0f GB used (%.0f%%)", memUsed, memTotal, pct))
            }
        }
        if diskEnabled, diskFree > 0, diskFree <= diskFreeThresholdGB {
            fire("disk", "Low disk space", String(format: "Only %.1f GB free", diskFree))
        }
        if gpuEnabled, gpu >= gpuThreshold {
            fire("gpu", "High GPU usage", String(format: "GPU is at %.0f%%", gpu))
        }
        if thermalEnabled, thermal == .serious || thermal == .critical {
            fire("thermal", "System running hot", "Thermal pressure: \(thermal.label)")
        }
    }

    private func fire(_ key: String, _ title: String, _ body: String) {
        let now = Date()
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
