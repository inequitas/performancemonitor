import Foundation
import IOKit
import IOKit.ps

/// Battery-health details, refreshed on a throttled cadence (every 60s).
///
/// `.unavailable` mirrors the original failure path, where only `batteryCycleCount`
/// is nilled and every other field is left untouched. In `.values`,
/// `cycleCount`/`designCycleCount`/`healthPercent`/`amperage` are always applied
/// (nil means "set to nil"), whereas `temperatureC`/`voltage`/`condition` are
/// applied only when non-nil (nil means "keep previous"), matching the original.
enum BatteryHealthSnapshot {
    case unavailable
    case values(cycleCount: Int?,
                designCycleCount: Int?,
                healthPercent: Double?,
                temperatureC: Double?,
                voltage: Double?,
                amperage: Int?,
                condition: String?)
}

/// Immutable result of one battery sample.
enum BatterySnapshot {
    case noBattery
    case present(percent: Int?,
                 isCharging: Bool,
                 timeRemainingMinutes: Int?,
                 powerSourceName: String,
                 /// `nil` on samples where the 60s health throttle did not fire —
                 /// the engine keeps its previous health values.
                 health: BatteryHealthSnapshot?)
}

protocol BatterySampling: AnyObject {
    /// Reads power-source info (and, throttled, battery health) off the main
    /// thread. Returns `.noBattery` when a previous call is still in flight,
    /// matching the "nothing to report" path the engine already handles.
    func sample() async -> BatterySnapshot
}

private struct RawHealthRead: Sendable {
    let cycleCount: Int?
    let designCycleCount: Int?
    let healthPercent: Double?
    let temperatureC: Double?
    let voltage: Double?
    let amperage: Int?
    let condition: String?
    let available: Bool
}

/// Owns the battery-health refresh throttle. The IOKit power-source/battery
/// reads run detached from the main thread; the 60s throttle check (a cheap
/// Date compare) stays on the main actor. Extracted verbatim from
/// `MetricsEngine.updateBattery`/`updateBatteryHealth`.
@MainActor
final class BatterySampler: BatterySampling {
    private var healthCacheDate: Date = .distantPast
    private var inFlight = false

    func sample() async -> BatterySnapshot {
        guard !inFlight else { return .noBattery }
        inFlight = true
        defer { inFlight = false }

        let now = Date()
        let shouldReadHealth = now.timeIntervalSince(healthCacheDate) > 60
        if shouldReadHealth { healthCacheDate = now }

        guard let raw = await Self.readRaw(includeHealth: shouldReadHealth) else { return .noBattery }

        let health: BatteryHealthSnapshot?
        if let h = raw.health {
            health = h.available
                ? .values(cycleCount: h.cycleCount, designCycleCount: h.designCycleCount,
                          healthPercent: h.healthPercent, temperatureC: h.temperatureC,
                          voltage: h.voltage, amperage: h.amperage, condition: h.condition)
                : .unavailable
        } else {
            health = nil
        }

        return .present(percent: raw.percent,
                        isCharging: raw.isCharging,
                        timeRemainingMinutes: raw.timeRemaining,
                        powerSourceName: raw.powerSourceName,
                        health: health)
    }

    /// Pure IOKit reads, no shared state — safe to run detached.
    private static func readRaw(includeHealth: Bool) async -> (percent: Int?, isCharging: Bool, timeRemaining: Int?, powerSourceName: String, health: RawHealthRead?)? {
        await Task.detached(priority: .utility) { () -> (percent: Int?, isCharging: Bool, timeRemaining: Int?, powerSourceName: String, health: RawHealthRead?)? in
            guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
                  let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
                  let source = sources.first,
                  let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
                return nil
            }

            let percent = info[kIOPSCurrentCapacityKey] as? Int
            let state = info[kIOPSPowerSourceStateKey] as? String
            let isCharging = (state == kIOPSACPowerValue)
            let powerSourceName = isCharging ? "AC Power" : "Battery"

            let timeRemaining: Int?
            if let timeToEmpty = info[kIOPSTimeToEmptyKey] as? Int, timeToEmpty >= 0, !isCharging {
                timeRemaining = timeToEmpty
            } else if let timeToFull = info[kIOPSTimeToFullChargeKey] as? Int, timeToFull >= 0, isCharging {
                timeRemaining = timeToFull
            } else {
                timeRemaining = nil
            }

            let health = includeHealth ? readHealth() : nil

            return (percent: percent, isCharging: isCharging, timeRemaining: timeRemaining,
                    powerSourceName: powerSourceName, health: health)
        }.value
    }

    /// Pure IOKit read, no shared state — marked `nonisolated` so it can be
    /// called from the detached (non-main-actor) closure in `readRaw`.
    private nonisolated static func readHealth() -> RawHealthRead {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else {
            return RawHealthRead(cycleCount: nil, designCycleCount: nil, healthPercent: nil,
                                 temperatureC: nil, voltage: nil, amperage: nil, condition: nil, available: false)
        }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return RawHealthRead(cycleCount: nil, designCycleCount: nil, healthPercent: nil,
                                 temperatureC: nil, voltage: nil, amperage: nil, condition: nil, available: false)
        }

        let cycleCount = props["CycleCount"] as? Int
        let designCycleCount = props["DesignCycleCount9C"] as? Int

        let healthPercent: Double?
        if let designCapacity = props["DesignCapacity"] as? Int, designCapacity > 0,
           let nominalCapacity = props["NominalChargeCapacity"] as? Int {
            healthPercent = (Double(nominalCapacity) / Double(designCapacity)) * 100
        } else {
            healthPercent = nil
        }

        // temperatureC / voltage stay nil when absent → engine keeps previous.
        var temperatureC: Double? = nil
        if let temp = props["Temperature"] as? Int {
            temperatureC = Double(temp) / 100.0
        }
        var voltage: Double? = nil
        if let v = props["Voltage"] as? Int {
            voltage = Double(v) / 1000.0
        }
        let amperage = props["Amperage"] as? Int

        // Original only updates `batteryCondition` when a health % is available.
        let condition: String? = healthPercent.map { $0 >= 80 ? "Normal" : "Service Recommended" }

        return RawHealthRead(cycleCount: cycleCount, designCycleCount: designCycleCount,
                             healthPercent: healthPercent, temperatureC: temperatureC,
                             voltage: voltage, amperage: amperage, condition: condition, available: true)
    }
}
