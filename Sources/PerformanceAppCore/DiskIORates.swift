import Foundation

/// Cumulative disk read/write byte counters for one process, as reported by
/// `proc_pid_rusage` (`ri_diskio_bytesread` / `ri_diskio_byteswritten`).
public struct DiskIOBytes: Equatable, Sendable {
    public let read: Double
    public let written: Double

    public init(read: Double, written: Double) {
        self.read = read
        self.written = written
    }
}

/// Pure rate calculator for per-process disk I/O, mirroring `NettopParser.rates`.
///
/// The kernel exposes cumulative per-process byte counters, so throughput is a
/// delta between two snapshots; this turns two counter snapshots into per-process
/// kB/s rows.
///
/// **Own-user limitation:** the counters come from `proc_pid_rusage`, which
/// without root only succeeds for processes owned by the current user. System
/// processes (`kernel_task`, `WindowServer`, `mds`, …) are therefore absent from
/// the snapshots and from the result. This is *not* a complete, system-wide
/// ranking and must be labelled as such wherever it is displayed.
public enum DiskIORates {
    /// Computes per-process disk throughput (kB/s) from two counter snapshots
    /// keyed by pid.
    ///
    /// Read and write deltas are clamped at zero individually so a counter reset
    /// can never produce a negative rate. Only processes moving more than
    /// 0.05 kB/s are kept. Returns the `topCount` busiest processes, highest
    /// first.
    ///
    /// A pid whose name differs between the two snapshots is skipped entirely
    /// for this round: macOS recycles pids, so diffing a recycled pid against
    /// the counters of the process that previously held it would report a huge
    /// bogus spike. Such a pid establishes its baseline on this round and only
    /// reports a rate from the next one onwards.
    public static func rates(current: [Int32: DiskIOBytes],
                             previous: [Int32: DiskIOBytes],
                             names: [Int32: String],
                             previousNames: [Int32: String],
                             elapsed: Double,
                             topCount: Int) -> [ProcessUsage] {
        guard elapsed > 0 else { return [] }
        var list: [ProcessUsage] = []
        for (pid, bytes) in current {
            let name = names[pid] ?? "PID \(pid)"
            // PID reuse: the pid now belongs to a different process, so its
            // previous counters are not a valid baseline.
            if let previousName = previousNames[pid], previousName != name { continue }
            let prev = previous[pid] ?? DiskIOBytes(read: 0, written: 0)
            let deltaRead = Swift.max(bytes.read - prev.read, 0)
            let deltaWritten = Swift.max(bytes.written - prev.written, 0)
            let kbps = (deltaRead + deltaWritten) / elapsed / 1024
            if kbps > 0.05 {
                list.append(ProcessUsage(pid: pid, name: name, value: kbps))
            }
        }
        return Array(list.sorted { $0.value > $1.value }.prefix(topCount))
    }
}
