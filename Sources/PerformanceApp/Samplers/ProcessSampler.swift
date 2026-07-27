import Darwin
import Foundation
import PerformanceAppCore

/// Immutable result of one `ps` sample.
struct ProcessSnapshot {
    let topCPU: [ProcessUsage]
    let topMemory: [ProcessUsage]
}

@MainActor
protocol ProcessSampling: AnyObject {
    /// Runs `ps` off the main thread and parses the top CPU/memory consumers.
    /// Returns `nil` while a previous run is still in flight, the launch failed,
    /// or the 3s cadence throttle blocks this call.
    func sample(topCount: Int) async -> ProcessSnapshot?
    /// Clears the cadence throttle so the next `sample` call runs immediately.
    /// Called when a window showing process lists becomes visible, so the user
    /// doesn't see a stale/empty list while waiting for the next natural tick.
    func resetThrottle()
}

/// Owns the in-flight guard and the 3s cadence throttle for the `ps` sampler.
/// `ps` is only sampled while a window that displays it (CPU/Memory detail) is
/// visible — see `MetricsEngine.setPanelVisible` — so this throttle caps the
/// cost while visible rather than gating visibility itself.
@MainActor
final class ProcessSampler: ProcessSampling {
    private var inFlight = false
    private var cacheDate: Date = .distantPast
    private static let interval: TimeInterval = 3

    func sample(topCount: Int) async -> ProcessSnapshot? {
        guard !inFlight else { return nil }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) >= Self.interval else { return nil }
        inFlight = true
        cacheDate = now
        defer { inFlight = false }

        let logicalCPUs = Double(ProcessInfo.processInfo.processorCount)
        guard let output = await ProcessSampler.runPS() else { return nil }
        let (cpu, mem) = PSParser.parse(output, topCount: topCount, logicalCPUs: logicalCPUs)
        return ProcessSnapshot(topCPU: cpu, topMemory: mem)
    }

    func resetThrottle() { cacheDate = .distantPast }

    private static func runPS() async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/bin/ps")
            task.arguments = ["-arcwwwxo", "pid,comm,%cpu,%mem"]
            let outPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = Pipe()
            guard (try? task.run()) != nil else { return nil }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}

/// Immutable result of one `nettop` sample: per-app network throughput.
@MainActor
protocol NetworkProcessSampling: AnyObject {
    /// Runs `nettop` off the main thread and computes per-app kB/s throughput.
    /// Returns `nil` while a previous run is in flight, the launch failed, the
    /// 3s cadence throttle blocks this call, or there is no previous snapshot
    /// yet to diff against.
    func sample(topCount: Int) async -> [ProcessUsage]?
    /// Clears the cadence throttle so the next `sample` call runs immediately.
    /// Called when the Network detail window becomes visible.
    func resetThrottle()
    /// Drops the previous byte-counter baseline. Called when the Network detail
    /// window becomes invisible (sampling pauses) so that, on the next visible
    /// sample, a fresh baseline is established instead of computing a rate
    /// averaged over the whole invisible interval.
    func invalidateBaseline()
}

/// Owns the in-flight guard, the 3s cadence throttle, and the previous byte
/// counters/timestamp for the `nettop` sampler. `nettop` is only sampled while
/// the Network detail window is visible — see `MetricsEngine.setPanelVisible`.
@MainActor
final class NetworkProcessSampler: NetworkProcessSampling {
    private var inFlight = false
    private var cacheDate: Date = .distantPast
    private static let interval: TimeInterval = 3
    private var previousBytes: [String: NetBytes] = [:]
    private var previousTimestamp: Date?

    func sample(topCount: Int) async -> [ProcessUsage]? {
        guard !inFlight else { return nil }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) >= Self.interval else { return nil }
        inFlight = true
        cacheDate = now
        defer { inFlight = false }

        guard let output = await NetworkProcessSampler.runNettop() else { return nil }
        let current = NettopParser.parse(output)

        var result: [ProcessUsage]? = nil
        if let prevTime = previousTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                result = NettopParser.rates(current: current, previous: previousBytes,
                                            elapsed: elapsed, topCount: topCount)
            }
        }
        previousBytes = current
        previousTimestamp = now
        return result
    }

    func resetThrottle() { cacheDate = .distantPast }

    func invalidateBaseline() {
        previousBytes = [:]
        previousTimestamp = nil
    }

    private static func runNettop() async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/nettop")
            task.arguments = ["-P", "-x", "-L", "1", "-J", "bytes_in,bytes_out"]
            let outPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = Pipe()
            guard (try? task.run()) != nil else { return nil }
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8) ?? ""
        }.value
    }
}

/// One `proc_pid_rusage` sweep: cumulative disk byte counters plus the process
/// name that owned each pid at sample time (the name is what lets the rate
/// calculator detect pid reuse).
struct DiskIOSnapshot: Sendable {
    let bytes: [Int32: DiskIOBytes]
    let names: [Int32: String]
}

@MainActor
protocol DiskProcessSampling: AnyObject {
    /// Reads per-process disk byte counters off the main thread and computes
    /// per-process kB/s throughput. Returns `nil` while a previous run is in
    /// flight, the pid enumeration failed, the 3s cadence throttle blocks this
    /// call, or there is no previous snapshot yet to diff against.
    func sample(topCount: Int) async -> [ProcessUsage]?
    /// Clears the cadence throttle so the next `sample` call runs immediately.
    /// Called when the Disk detail window becomes visible.
    func resetThrottle()
    /// Drops the previous byte-counter baseline. Called when the Disk detail
    /// window becomes invisible (sampling pauses) so that, on the next visible
    /// sample, a fresh baseline is established instead of computing a rate
    /// averaged over the whole invisible interval.
    func invalidateBaseline()
}

/// Owns the in-flight guard, the 3s cadence throttle, and the previous byte
/// counters/timestamp for the per-process disk I/O sampler. Unlike the `ps` and
/// `nettop` samplers this spawns no subprocess — it is a plain syscall loop over
/// `proc_listpids` + `proc_pid_rusage` — but it is still only sampled while the
/// Disk detail window is visible; see `MetricsEngine.setPanelVisible`.
///
/// Without root, `proc_pid_rusage` only succeeds for processes owned by the
/// current user, so system processes are silently absent. See `DiskIORates`.
@MainActor
final class DiskProcessSampler: DiskProcessSampling {
    private var inFlight = false
    private var cacheDate: Date = .distantPast
    private static let interval: TimeInterval = 3
    private var previousBytes: [Int32: DiskIOBytes] = [:]
    private var previousNames: [Int32: String] = [:]
    private var previousTimestamp: Date?

    func sample(topCount: Int) async -> [ProcessUsage]? {
        guard !inFlight else { return nil }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) >= Self.interval else { return nil }
        inFlight = true
        cacheDate = now
        defer { inFlight = false }

        guard let snapshot = await DiskProcessSampler.readCounters() else { return nil }

        var result: [ProcessUsage]? = nil
        if let prevTime = previousTimestamp {
            let elapsed = now.timeIntervalSince(prevTime)
            if elapsed > 0 {
                result = DiskIORates.rates(current: snapshot.bytes, previous: previousBytes,
                                           names: snapshot.names, previousNames: previousNames,
                                           elapsed: elapsed, topCount: topCount)
            }
        }
        previousBytes = snapshot.bytes
        previousNames = snapshot.names
        previousTimestamp = now
        return result
    }

    func resetThrottle() { cacheDate = .distantPast }

    func invalidateBaseline() {
        previousBytes = [:]
        previousNames = [:]
        previousTimestamp = nil
    }

    private static func readCounters() async -> DiskIOSnapshot? {
        await Task.detached(priority: .utility) { () -> DiskIOSnapshot? in
            // Size the pid buffer, then fill it. The set of live pids can grow
            // between the two calls; the second call reports how many bytes it
            // actually wrote, so any excess capacity is simply dropped.
            let sizeBytes = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
            guard sizeBytes > 0 else { return nil }
            let capacity = Int(sizeBytes) / MemoryLayout<pid_t>.size
            guard capacity > 0 else { return nil }
            var pids = [pid_t](repeating: 0, count: capacity)
            let written = pids.withUnsafeMutableBufferPointer { buffer in
                proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress,
                              Int32(buffer.count * MemoryLayout<pid_t>.size))
            }
            guard written > 0 else { return nil }
            let count = Swift.min(Int(written) / MemoryLayout<pid_t>.size, capacity)

            var bytes: [Int32: DiskIOBytes] = [:]
            var names: [Int32: String] = [:]
            for pid in pids.prefix(count) where pid != 0 {
                var nameBuffer = [CChar](repeating: 0, count: Int(2 * MAXCOMLEN) + 1)
                guard proc_name(pid, &nameBuffer, UInt32(nameBuffer.count)) > 0 else { continue }
                var info = rusage_info_v4()
                let rc = withUnsafeMutablePointer(to: &info) {
                    $0.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) {
                        proc_pid_rusage(pid, RUSAGE_INFO_V4, $0)
                    }
                }
                // Expected common case: the process isn't ours, so the kernel
                // refuses. Skip it silently rather than logging every tick.
                guard rc == 0 else { continue }
                bytes[pid] = DiskIOBytes(read: Double(info.ri_diskio_bytesread),
                                         written: Double(info.ri_diskio_byteswritten))
                names[pid] = String(cString: nameBuffer)
            }
            return DiskIOSnapshot(bytes: bytes, names: names)
        }.value
    }
}
