import Foundation
import PerformanceAppCore

/// Immutable result of one SMC sample.
struct SMCSnapshot {
    let cpuTemperatureC: Double?
    let gpuTemperatureC: Double?
    let fans: [FanInfo]
    let extendedTemperatures: [TempReading]
    let unknownSMCTemperatures: [TempReading]
}

protocol SMCSampling: AnyObject {
    /// Reads all SMC temperatures/fans off the main thread, throttled to once
    /// every 2s. Returns `nil` when SMC is unavailable or the throttle blocks
    /// this call — the engine then leaves thermal state unchanged.
    func sample() async -> SMCSnapshot?
}

/// Owns the `SMCReader` handle and the 2s read throttle. `SMCReader` is
/// `@unchecked Sendable` and is only ever touched from this sampler.
/// Extracted verbatim from `MetricsEngine.updateSMC`.
@MainActor
final class SMCSampler: SMCSampling {
    private let smc = SMCReader()
    private var cacheDate: Date = .distantPast

    func sample() async -> SMCSnapshot? {
        guard smc.isOpen else { return nil }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) > 2 else { return nil }
        cacheDate = now
        let reader = smc  // capture before leaving @MainActor; SMCReader is @unchecked Sendable
        return await Task.detached(priority: .utility) { () -> SMCSnapshot in
            let cpuT     = reader.cpuTemperature()
            let gpuT     = reader.gpuTemperature()
            let f        = reader.fans()
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
                               unknownSMCTemperatures: unknown)
        }.value
    }
}
