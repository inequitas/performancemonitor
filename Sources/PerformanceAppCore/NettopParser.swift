import Foundation

/// Cumulative in/out byte counters for one process, as reported by `nettop`.
public struct NetBytes: Equatable {
    public let bytesIn: Double
    public let bytesOut: Double

    public init(bytesIn: Double, bytesOut: Double) {
        self.bytesIn = bytesIn
        self.bytesOut = bytesOut
    }
}

/// Pure parser + rate calculator for `nettop -P -x -L 1 -J bytes_in,bytes_out`.
///
/// Extracted from `MetricsEngine.updateNetworkProcesses` in the Part-B
/// decomposition. `nettop` reports cumulative byte counters, so throughput is a
/// delta between two samples; `parse` turns raw output into counters and `rates`
/// turns two counter snapshots into per-process kB/s.
public enum NettopParser {
    /// Parses a single `nettop` snapshot into cumulative counters keyed by the
    /// process column (first field). The header row is dropped.
    public static func parse(_ output: String) -> [String: NetBytes] {
        let lines = output.split(separator: "\n").dropFirst()
        var current: [String: NetBytes] = [:]
        for line in lines {
            let parts = line.split(separator: ",", omittingEmptySubsequences: false)
            guard parts.count >= 3 else { continue }
            let name = String(parts[0])
            guard let bytesIn = Double(parts[1]), let bytesOut = Double(parts[2]) else { continue }
            current[name] = NetBytes(bytesIn: bytesIn, bytesOut: bytesOut)
        }
        return current
    }

    /// Computes per-process throughput (kB/s) from two counter snapshots.
    ///
    /// Only processes moving more than 0.05 kB/s are kept; the display name drops
    /// the trailing PID-ish component (`Safari.12345` → `Safari`). Returns the
    /// `topCount` busiest processes, highest first.
    public static func rates(current: [String: NetBytes],
                             previous: [String: NetBytes],
                             elapsed: Double,
                             topCount: Int) -> [ProcessUsage] {
        guard elapsed > 0 else { return [] }
        var list: [ProcessUsage] = []
        for (name, bytes) in current {
            let prev = previous[name] ?? NetBytes(bytesIn: 0, bytesOut: 0)
            let deltaIn = Swift.max(bytes.bytesIn - prev.bytesIn, 0)
            let deltaOut = Swift.max(bytes.bytesOut - prev.bytesOut, 0)
            let kbps = (deltaIn + deltaOut) / elapsed / 1024
            if kbps > 0.05 {
                let displayName = name.split(separator: ".").dropLast().joined(separator: ".")
                list.append(ProcessUsage(pid: 0, name: displayName.isEmpty ? name : displayName, value: kbps))
            }
        }
        return Array(list.sorted { $0.value > $1.value }.prefix(topCount))
    }
}
