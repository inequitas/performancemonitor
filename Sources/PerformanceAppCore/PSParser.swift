import Foundation

/// Pure parser for the output of `ps -arcwwwxo pid,ppid,%cpu,%mem,comm`.
///
/// The first line (the column header) is dropped; each remaining line is
/// `pid ppid %cpu %mem comm...`, where the command name may contain spaces and
/// runs to the end of the line.
///
/// The column order matters. `ps` gives every column except the last a fixed
/// width, so asking for `comm` anywhere but last silently truncates process
/// names to 16 characters: "Performance Monitor" arrives as "Performance Moni"
/// and three different WebKit helpers all arrive as "com.apple.WebKit". Putting
/// it last lets it run to full length, which the process lists show and the
/// glossary needs in order to tell those helpers apart.
///
/// `ppid` costs nothing extra: it comes from the same `ps` run, and it is what
/// lets `ProcessGrouping` fold an app's helpers into one row.
public enum PSParser {
    /// Parses `ps` output into the top CPU and top memory consumers, with each
    /// app's helper processes grouped into a single row.
    ///
    /// - Parameters:
    ///   - output: Raw stdout of the `ps` invocation (including the header row).
    ///   - topCount: How many rows to keep per list.
    ///   - logicalCPUs: Logical CPU count, used to rescale `ps`'s per-core `%cpu`
    ///     (a process pinning two cores reports 200%) into a share of total
    ///     system capacity. Clamped to `1...256`.
    /// - Returns: The `topCount` heaviest CPU rows and memory rows. Grouping
    ///   happens across every parsed line before the lists are trimmed, because
    ///   a helper that falls outside the top on its own still counts towards the
    ///   group it belongs to.
    public static func parse(_ output: String,
                             topCount: Int,
                             logicalCPUs: Double) -> (cpu: [ProcessUsage], memory: [ProcessUsage]) {
        let lines = output.split(separator: "\n").dropFirst()
        let cpus = Swift.min(Swift.max(logicalCPUs, 1), 256)

        var cpuList: [ProcessUsage] = []
        var memList: [ProcessUsage] = []
        var parents: [Int32: Int32] = [:]
        for line in lines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 5,
                  let pid = Int32(parts[0]),
                  let ppid = Int32(parts[1]),
                  let rawCPU = Double(parts[2]),
                  let mem = Double(parts[3]) else { continue }
            let name = parts[4...].joined(separator: " ")
            let cpu = (rawCPU / cpus * 10).rounded() / 10
            parents[pid] = ppid
            cpuList.append(ProcessUsage(pid: pid, name: name, value: cpu))
            memList.append(ProcessUsage(pid: pid, name: name, value: mem))
        }

        return (ProcessGrouping.group(cpuList, parents: parents, topCount: topCount),
                ProcessGrouping.group(memList, parents: parents, topCount: topCount))
    }
}
