import Foundation
import PerformanceAppCore

/// Immutable result of one SMC sample.
struct SMCSnapshot {
    let cpuTemperatureC: Double?
    let gpuTemperatureC: Double?
    let fans: [FanInfo]
    let extendedTemperatures: [TempReading]
    let unknownSMCTemperatures: [TempReading]
    let systemPowerWatts: Double?
}

protocol SMCSampling: AnyObject {
    /// Reads SMC temperatures off the main thread, throttled to once every 2s.
    /// Returns `nil` when SMC is unavailable or the throttle blocks this call —
    /// the engine then leaves thermal state unchanged.
    ///
    /// When `extended` is false (menu bar / popover only), reads just the CPU
    /// and GPU averages — the only per-sensor values observed outside the
    /// Thermal detail window — and leaves the fan/extended/power fields empty.
    /// When `extended` is true (Thermal window visible), reads the full sensor
    /// set, fans, and system power.
    func sample(extended: Bool) async -> SMCSnapshot?

    /// Clears the 2s throttle so the next `sample` reads immediately. Used when
    /// the Thermal window opens, so it shows the full sensor set at once.
    func resetThrottle()
}

/// Owns the `SMCReader` handle and the 2s read throttle. `SMCReader` is
/// `@unchecked Sendable` and is only ever touched from this sampler.
/// Extracted verbatim from `MetricsEngine.updateSMC`.
@MainActor
final class SMCSampler: SMCSampling {
    private let smc = SMCReader()
    private var cacheDate: Date = .distantPast

    func resetThrottle() { cacheDate = .distantPast }

    func sample(extended: Bool) async -> SMCSnapshot? {
        guard smc.isOpen else { return nil }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) > 2 else { return nil }
        cacheDate = now
        let reader = smc  // capture before leaving @MainActor; SMCReader is @unchecked Sendable

        // Minimal path: menu bar and popover only need the CPU/GPU averages.
        // This skips enumerating and reading every SMC key — the dominant idle
        // cost — and only the Thermal window pays for the full set below.
        guard extended else {
            return await Task.detached(priority: .utility) { () -> SMCSnapshot in
                let (cpuT, gpuT) = reader.averageCPUGPUTemperatures()
                return SMCSnapshot(cpuTemperatureC: cpuT,
                                   gpuTemperatureC: gpuT,
                                   fans: [],
                                   extendedTemperatures: [],
                                   unknownSMCTemperatures: [],
                                   systemPowerWatts: nil)
            }.value
        }

        return await Task.detached(priority: .utility) { () -> SMCSnapshot in
            let cpuT     = reader.cpuTemperature()
            let gpuT     = reader.gpuTemperature()
            let f        = reader.fans()
            let power    = reader.systemPowerWatts()
            let allTemps = reader.readAllTemperatures()
            var known: [TempReading] = []
            var unknown: [TempReading] = []
            for (key, value) in allTemps {
                if let (label, category) = SMCSensorCatalog.categorize(key: key) {
                    known.append(TempReading(key: key, label: label, category: category, celsius: value))
                } else {
                    unknown.append(TempReading(key: key, label: key, category: "Unknown", celsius: value))
                }
            }
            // Derive CPU/GPU averages from extended sensors when available.
            // This handles M3/M4 which use Te*/Tf* keys that cpuTemperature()/
            // gpuTemperature() won't find (those only look for Tp*/Tg* prefixes).
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
            return SMCSnapshot(cpuTemperatureC: finalCpuT,
                               gpuTemperatureC: finalGpuT,
                               fans: f,
                               extendedTemperatures: known,
                               unknownSMCTemperatures: unknown,
                               systemPowerWatts: power)
        }.value
    }
}
