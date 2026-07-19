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
}

protocol MemorySampling: AnyObject {
    /// Reads virtual-memory statistics, or `nil` if the kernel query fails
    /// (engine then leaves memory state untouched).
    func sample() -> MemorySnapshot?
}

/// Stateless memory reader. Extracted verbatim from `MetricsEngine.updateMemory`
/// in the Part-B decomposition.
final class MemorySampler: MemorySampling {
    func sample() -> MemorySnapshot? {
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

        return MemorySnapshot(
            usedGB: used / 1_073_741_824,
            totalGB: total / 1_073_741_824,
            appGB: Double(stats.active_count + stats.inactive_count) * pageSize / 1_073_741_824,
            wiredGB: Double(stats.wire_count) * pageSize / 1_073_741_824,
            compressedGB: Double(stats.compressor_page_count) * pageSize / 1_073_741_824,
            swapUsedGB: swapUsedGB
        )
    }
}
