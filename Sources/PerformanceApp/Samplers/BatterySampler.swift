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
    func sample() -> BatterySnapshot
}

/// Owns the battery-health refresh throttle. Extracted verbatim from
/// `MetricsEngine.updateBattery`/`updateBatteryHealth`.
final class BatterySampler: BatterySampling {
    private var healthCacheDate: Date = .distantPast

    func sample() -> BatterySnapshot {
        guard let snapshot = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(snapshot)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any] else {
            return .noBattery
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

        var health: BatteryHealthSnapshot? = nil
        let now = Date()
        if now.timeIntervalSince(healthCacheDate) > 60 {
            healthCacheDate = now
            health = readHealth()
        }

        return .present(percent: percent,
                        isCharging: isCharging,
                        timeRemainingMinutes: timeRemaining,
                        powerSourceName: powerSourceName,
                        health: health)
    }

    private func readHealth() -> BatteryHealthSnapshot {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return .unavailable }
        defer { IOObjectRelease(service) }

        var propsRef: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &propsRef, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let props = propsRef?.takeRetainedValue() as? [String: Any] else {
            return .unavailable
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

        return .values(cycleCount: cycleCount,
                       designCycleCount: designCycleCount,
                       healthPercent: healthPercent,
                       temperatureC: temperatureC,
                       voltage: voltage,
                       amperage: amperage,
                       condition: condition)
    }
}
