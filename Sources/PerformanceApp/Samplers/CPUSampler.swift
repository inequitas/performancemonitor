import Foundation
import Darwin

/// Immutable result of one CPU sample.
struct CPUSnapshot {
    let usagePercent: Double
    let userPercent: Double
    let systemPercent: Double
    let perCore: [Double]
    let loadAverages: (one: Double, five: Double, fifteen: Double)
}

protocol CPUSampling: AnyObject {
    /// Reads current CPU tick counters off the main thread and returns usage
    /// relative to the previous sample, or `nil` if the kernel query fails or a
    /// previous call is still in flight (engine then leaves CPU state
    /// untouched). The first successful call has no baseline, so it reports 0%
    /// usage and an empty per-core array while still returning load averages.
    func sample() async -> CPUSnapshot?
}

private typealias CoreTicks = (user: UInt32, system: UInt32, idle: UInt32, nice: UInt32)
private typealias RawCPURead = (ticksPerCore: [CoreTicks], loadAverages: (one: Double, five: Double, fifteen: Double))

/// Owns the previous per-core tick counters and derives usage deltas.
/// The mach `host_processor_info` call runs off the main thread; the (cheap,
/// CPU-only) delta math against `previousTicks` stays on the main actor.
/// Extracted verbatim from `MetricsEngine.updateCPU` in the Part-B decomposition.
@MainActor
final class CPUSampler: CPUSampling {
    private var previousTicks: [CoreTicks] = []
    private var inFlight = false

    func sample() async -> CPUSnapshot? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }

        guard let raw = await Self.readRaw() else { return nil }
        let ticksPerCore = raw.ticksPerCore

        var usagePercent: Double = 0
        var userPercent: Double = 0
        var systemPercent: Double = 0
        var perCore: [Double] = []

        if previousTicks.count == ticksPerCore.count {
            var coreUsages: [Double] = []
            var totalUser: Double = 0
            var totalSystem: Double = 0
            var totalNice: Double = 0
            var totalTicks: Double = 0

            for i in 0..<ticksPerCore.count {
                let prev = previousTicks[i]
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

            perCore = coreUsages
            usagePercent = totalTicks > 0 ? ((totalUser + totalSystem + totalNice) / totalTicks) * 100 : 0
            userPercent = totalTicks > 0 ? (totalUser / totalTicks) * 100 : 0
            systemPercent = totalTicks > 0 ? (totalSystem / totalTicks) * 100 : 0
        }

        previousTicks = ticksPerCore

        return CPUSnapshot(usagePercent: usagePercent,
                           userPercent: userPercent,
                           systemPercent: systemPercent,
                           perCore: perCore,
                           loadAverages: raw.loadAverages)
    }

    /// Reads the raw per-core tick counters and load averages off the main
    /// thread. Pure syscalls, no shared state — safe to run detached.
    private static func readRaw() async -> RawCPURead? {
        await Task.detached(priority: .utility) { () -> RawCPURead? in
            var numCPUsU: natural_t = 0
            var cpuInfo: processor_info_array_t!
            var numCPUInfo: mach_msg_type_number_t = 0

            let result = host_processor_info(mach_host_self(),
                                             PROCESSOR_CPU_LOAD_INFO,
                                             &numCPUsU,
                                             &cpuInfo,
                                             &numCPUInfo)
            guard result == KERN_SUCCESS else { return nil }

            let numCPUs = Int(numCPUsU)
            var ticksPerCore: [CoreTicks] = []
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

            var loadAverages: (one: Double, five: Double, fifteen: Double) = (0, 0, 0)
            var loadavg = [Double](repeating: 0, count: 3)
            if getloadavg(&loadavg, 3) == 3 {
                loadAverages = (loadavg[0], loadavg[1], loadavg[2])
            }

            return (ticksPerCore: ticksPerCore, loadAverages: loadAverages)
        }.value
    }
}
