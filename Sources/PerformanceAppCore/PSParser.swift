import Foundation

/// Pure parser for the output of `ps -arcwwwxo pid,comm,%cpu,%mem`.
///
/// Extracted from `MetricsEngine.updateProcesses` in the Part-B decomposition.
/// The first line (the column header) is dropped; each remaining line is
/// `pid comm... %cpu %mem`, where the command name may contain spaces.
public enum PSParser {
    /// Parses `ps` output into the top CPU and top memory consumers.
    ///
    /// - Parameters:
    ///   - output: Raw stdout of the `ps` invocation (including the header row).
    ///   - topCount: How many rows to keep per list.
    ///   - logicalCPUs: Logical CPU count, used to rescale `ps`'s per-core `%cpu`
    ///     (a process pinning two cores reports 200%) into a share of total
    ///     system capacity. Clamped to `1...256`.
    /// - Returns: The `topCount` highest CPU rows and `topCount` highest memory rows.
    public static func parse(_ output: String,
                             topCount: Int,
                             logicalCPUs: Double) -> (cpu: [ProcessUsage], memory: [ProcessUsage]) {
        let lines = output.split(separator: "\n").dropFirst()
        let cpus = Swift.min(Swift.max(logicalCPUs, 1), 256)

        var cpuList: [ProcessUsage] = []
        var memList: [ProcessUsage] = []
        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 4,
                  let pid = Int32(parts[0]),
                  let rawCPU = Double(parts[parts.count - 2]),
                  let mem = Double(parts[parts.count - 1]) else { continue }
            let name = parts[1..<(parts.count - 2)].joined(separator: " ")
            let cpu = (rawCPU / cpus * 10).rounded() / 10
            cpuList.append(ProcessUsage(pid: pid, name: name, value: cpu))
            memList.append(ProcessUsage(pid: pid, name: name, value: mem))
        }

        let topCPU = Array(cpuList.sorted { $0.value > $1.value }.prefix(topCount))
        let topMem = Array(memList.sorted { $0.value > $1.value }.prefix(topCount))
        return (topCPU, topMem)
    }
}
