import Foundation
import PerformanceAppCore

/// Reads the system's own record of when the Mac slept and woke, so the history
/// graphs can say what happened rather than only what the numbers did.
///
/// `pmset -g log` is the only source for this that survives a restart, and it is
/// not cheap: measured at 1.96 seconds and 8.8 MB of output on the machine this
/// was written against. So it runs off the main thread, only while the History
/// window is open, and at most once every ten minutes. Nothing about it touches
/// the metrics tick.
///
/// Throttling is recorded separately, by the engine as it happens, because
/// nothing on the system keeps a log of it.
@MainActor
protocol SystemEventSampling: AnyObject {
    /// Returns sleep and wake events, or `nil` while a previous run is in
    /// flight, the throttle blocks this call, or `pmset` could not be run.
    func sample() async -> [SystemEvent]?
}

@MainActor
final class SystemEventSampler: SystemEventSampling {
    private var inFlight = false
    private var cacheDate: Date = .distantPast
    /// Long, because the log only changes when the machine sleeps, and reading
    /// it costs two seconds of a core.
    private static let interval: TimeInterval = 600

    func sample() async -> [SystemEvent]? {
        guard !inFlight else { return nil }
        let now = Date()
        guard now.timeIntervalSince(cacheDate) >= Self.interval else { return nil }
        inFlight = true
        cacheDate = now
        defer { inFlight = false }

        guard let output = await Self.runPMSet() else { return nil }
        return PMSetLogParser.parse(output)
    }

    private static func runPMSet() async -> String? {
        await Task.detached(priority: .utility) { () -> String? in
            let task = Process()
            task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
            task.arguments = ["-g", "log"]
            let outPipe = Pipe()
            task.standardOutput = outPipe
            task.standardError = Pipe()
            guard (try? task.run()) != nil else { return nil }
            // Read before waiting: the output runs to megabytes and a full pipe
            // would block pmset forever while we waited for it to exit.
            let data = outPipe.fileHandleForReading.readDataToEndOfFile()
            task.waitUntilExit()
            return String(data: data, encoding: .utf8)
        }.value
    }
}
