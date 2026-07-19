import Foundation
import PerformanceAppCore

/// Immutable result of one `ps` sample.
struct ProcessSnapshot {
    let topCPU: [ProcessUsage]
    let topMemory: [ProcessUsage]
}

protocol ProcessSampling: AnyObject {
    /// Runs `ps` off the main thread and parses the top CPU/memory consumers.
    /// Returns `nil` while a previous run is still in flight or the launch failed.
    func sample(topCount: Int) async -> ProcessSnapshot?
}

/// Owns the in-flight guard for the `ps` sampler.
/// Extracted verbatim from `MetricsEngine.updateProcesses`.
@MainActor
final class ProcessSampler: ProcessSampling {
    private var inFlight = false

    func sample(topCount: Int) async -> ProcessSnapshot? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }

        let logicalCPUs = Double(ProcessInfo.processInfo.processorCount)
        guard let output = await ProcessSampler.runPS() else { return nil }
        let (cpu, mem) = PSParser.parse(output, topCount: topCount, logicalCPUs: logicalCPUs)
        return ProcessSnapshot(topCPU: cpu, topMemory: mem)
    }

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
protocol NetworkProcessSampling: AnyObject {
    /// Runs `nettop` off the main thread and computes per-app kB/s throughput.
    /// Returns `nil` while a previous run is in flight, the launch failed, or
    /// there is no previous snapshot yet to diff against.
    func sample(topCount: Int) async -> [ProcessUsage]?
}

/// Owns the in-flight guard plus the previous byte counters/timestamp for the
/// `nettop` sampler. Extracted verbatim from `MetricsEngine.updateNetworkProcesses`.
@MainActor
final class NetworkProcessSampler: NetworkProcessSampling {
    private var inFlight = false
    private var previousBytes: [String: NetBytes] = [:]
    private var previousTimestamp: Date?

    func sample(topCount: Int) async -> [ProcessUsage]? {
        guard !inFlight else { return nil }
        inFlight = true
        defer { inFlight = false }

        guard let output = await NetworkProcessSampler.runNettop() else { return nil }
        let current = NettopParser.parse(output)

        let now = Date()
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
