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
