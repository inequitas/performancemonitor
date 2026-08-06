import Foundation
import Darwin

/// Immutable result of one memory sample. All figures are in GB.
struct MemorySnapshot {
    let usedGB: Double
    let totalGB: Double
    let appGB: Double
    let wiredGB: Double
    let compressedGB: Double
    /// `nil` when the swap sysctl failed — engine keeps its previous swap value.
    let swapUsedGB: Double?
    /// What macOS itself reports about memory pressure: 1 normal, 2 warning,
    /// 4 critical. This is the signal Activity Monitor's pressure graph is
    /// based on, and the only one that says anything about *now*.
    let pressureLevel: Int
    /// Pages moved between memory and disk per second, averaged over the gap
    /// since the previous sample. Zero on the first sample.
    ///
    /// The amount of swap in use says nothing about this. macOS never
    /// proactively takes swap back: a page written out during a busy moment
    /// stays on disk, costing nothing, until something reads it again. Only
    /// pages actually moving make a machine feel slow.
    let swapPagesPerSecond: Double
}

protocol MemorySampling: AnyObject {
    /// Reads virtual-memory statistics off the main thread, or `nil` if the
    /// kernel query fails or a previous call is still in flight (engine then
    /// leaves memory state untouched).
    func sample() async -> MemorySnapshot?
}

/// Stateless memory reader; the mach/sysctl calls run detached from the main
/// thread. Extracted verbatim from `MetricsEngine.updateMemory` in the Part-B
/// decomposition.
@MainActor
final class MemorySampler: MemorySampling {
    private var inFlight = false
    /// Previous cumulative swapin+swapout count and when it was read, to turn
    /// the kernel's running totals into a rate.
    private var previousSwapPages: Double?
    private var previousRead: Date?

    func sample() async -> MemorySnapshot? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }
        let previousPages = previousSwapPages
        let elapsed = previousRead.map { Date().timeIntervalSince($0) } ?? 0
        let raw = await Task.detached(priority: .utility) { () -> (MemorySnapshot, Double)? in
            var stats = vm_statistics64()
            var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.stride / MemoryLayout<integer_t>.stride)
            let result = withUnsafeMutablePointer(to: &stats) {
                $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                    host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
                }
            }
            guard result == KERN_SUCCESS else { return nil }

            let pageSize = Double(vm_kernel_page_size)
            let used = Double(stats.active_count + stats.inactive_count + stats.wire_count) * pageSize
            let total = Double(ProcessInfo.processInfo.physicalMemory)

            var swapUsedGB: Double? = nil
            var swapUsage = xsw_usage()
            var size = MemoryLayout<xsw_usage>.stride
            if sysctlbyname("vm.swapusage", &swapUsage, &size, nil, 0) == 0 {
                swapUsedGB = Double(swapUsage.xsu_used) / 1_073_741_824
            }

            // 1 normal, 2 warning, 4 critical. Falls back to normal rather than
            // to alarm if the sysctl is ever missing, since a monitor that
            // invents pressure is worse than one that misses it.
            var level: Int32 = 1
            var levelSize = MemoryLayout<Int32>.stride
            if sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &levelSize, nil, 0) != 0 {
                level = 1
            }

            let pages = Double(stats.swapins) + Double(stats.swapouts)
            let snapshot = MemorySnapshot(
                usedGB: used / 1_073_741_824,
                totalGB: total / 1_073_741_824,
                appGB: Double(stats.active_count + stats.inactive_count) * pageSize / 1_073_741_824,
                wiredGB: Double(stats.wire_count) * pageSize / 1_073_741_824,
                compressedGB: Double(stats.compressor_page_count) * pageSize / 1_073_741_824,
                swapUsedGB: swapUsedGB,
                pressureLevel: Int(level),
                // Filled in by the caller, which owns the previous reading.
                swapPagesPerSecond: 0
            )
            return (snapshot, pages)
        }.value

        guard let (snapshot, pages) = raw else { return nil }
        // The counters only ever climb; a drop means the kernel reset them, so
        // treat it as a fresh baseline rather than reporting a negative rate.
        let rate: Double = {
            guard let previousPages, elapsed > 0, pages >= previousPages else { return 0 }
            return (pages - previousPages) / elapsed
        }()
        previousSwapPages = pages
        previousRead = Date()

        return MemorySnapshot(
            usedGB: snapshot.usedGB, totalGB: snapshot.totalGB, appGB: snapshot.appGB,
            wiredGB: snapshot.wiredGB, compressedGB: snapshot.compressedGB,
            swapUsedGB: snapshot.swapUsedGB, pressureLevel: snapshot.pressureLevel,
            swapPagesPerSecond: rate
        )
    }
}
