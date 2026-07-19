import Foundation
import MetricKit

/// Subscribes to MetricKit diagnostic payloads and writes any crash
/// diagnostics received to disk as JSON — entirely on-device, no network
/// call involved. This exists purely so a crash can be inspected after the
/// fact; nothing is ever transmitted anywhere, matching the app's
/// "no data collected" promise.
final class CrashReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = CrashReporter()

    /// `~/Library/Application Support/PerformanceApp/CrashReports`
    static var reportsDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerformanceApp", isDirectory: true)
            .appendingPathComponent("CrashReports", isDirectory: true)
    }

    // NSDateFormatter has been documented thread-safe for read/format use
    // since macOS 10.9; MetricKit can deliver payloads on a background queue.
    private static let filenameFormatter: DateFormatter = {
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd'T'HH-mm-ss"
        df.locale = Locale(identifier: "en_US_POSIX")
        df.timeZone = .current
        return df
    }()

    private override init() { super.init() }

    /// Registers with MetricKit. Call once at launch.
    func start() {
        MXMetricManager.shared.add(self)
    }

    // Called by MetricKit, possibly on a background queue, whenever new
    // diagnostic payloads are available (typically the next launch after a
    // crash, hang, etc.). Only crash diagnostics are persisted.
    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let crashPayloads = payloads.filter { !($0.crashDiagnostics ?? []).isEmpty }
        guard !crashPayloads.isEmpty else { return }

        let dir = Self.reportsDirectory
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        for payload in crashPayloads {
            let data = payload.jsonRepresentation()
            let name = "crash-\(Self.filenameFormatter.string(from: Date()))-\(UUID().uuidString.prefix(8)).json"
            try? data.write(to: dir.appendingPathComponent(name), options: .atomic)
        }
    }
}
