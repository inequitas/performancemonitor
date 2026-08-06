import Foundation
import PerformanceAppCore

/// Writes the current readings to a JSON file, for status-bar tools that render
/// their own display: SwiftBar, xbar, SketchyBar and anything else that can run
/// a script every few seconds.
///
/// Those tools want to poll, and polling `ps` and the SMC themselves would mean
/// a second program measuring the same machine. Reading one small file instead
/// costs them nothing and costs us one write.
///
/// Off unless asked for. It is a file that appears in someone's home directory
/// and a write on a timer, neither of which should happen because an app was
/// installed. When enabled it writes at most once every five seconds, which is
/// faster than any of those tools refresh.
///
/// Written to a temporary file and moved into place, so a reader polling on its
/// own schedule never catches a half-written file and reports nothing.
@MainActor
final class SnapshotWriter {

    /// `~/Library/Application Support/PerformanceApp/snapshot.json`, alongside
    /// the history database rather than somewhere new to explain.
    static var url: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerformanceApp", isDirectory: true)
            .appendingPathComponent("snapshot.json")
    }

    private static let interval: TimeInterval = 5
    private var lastWrite: Date = .distantPast
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        // Sorted so a diff between two snapshots shows what changed rather than
        // what moved, and pretty so `cat` is a reasonable way to look at it.
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// Writes if enabled and the interval has passed. Cheap and safe to call on
    /// every tick.
    func write(_ snapshot: Snapshot, enabled: Bool) {
        guard enabled else {
            // Turning the setting off takes the file with it, so nothing is left
            // to be read as current long after it stopped being.
            if lastWrite != .distantPast {
                lastWrite = .distantPast
                removeFile()
            }
            return
        }
        let now = Date()
        guard now.timeIntervalSince(lastWrite) >= Self.interval else { return }
        lastWrite = now

        guard let data = try? encoder.encode(snapshot) else { return }
        let destination = Self.url
        Task.detached(priority: .utility) {
            let directory = destination.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let temporary = directory.appendingPathComponent("snapshot.json.tmp")
            guard (try? data.write(to: temporary)) != nil else { return }
            _ = try? FileManager.default.replaceItemAt(destination, withItemAt: temporary)
        }
    }

    /// Removes the file when the setting is turned off, so disabling the feature
    /// leaves nothing behind to be read as current long after it stopped being.
    func removeFile() {
        let url = Self.url
        Task.detached(priority: .utility) {
            try? FileManager.default.removeItem(at: url)
        }
    }

    // MARK: - Shape

    /// What ends up in the file.
    ///
    /// Field names are part of the contract once someone writes a script against
    /// them, so they are spelled out rather than derived, and units are in the
    /// name where there could be any doubt.
    struct Snapshot: Encodable {
        struct Finding: Encodable {
            let topic: String
            let severity: String
            let message: String
            let advice: String
        }

        let schema: Int
        let timestamp: Date
        let cpuPercent: Double
        let memoryUsedGB: Double
        let memoryTotalGB: Double
        let memoryPercent: Double
        let swapUsedGB: Double
        let memoryPressure: String
        let diskFreeGB: Double
        let diskTotalGB: Double
        let downloadKBps: Double
        let uploadKBps: Double
        let cpuTemperatureC: Double?
        let gpuTemperatureC: Double?
        let thermalState: String
        let batteryPercent: Int?
        let batteryCharging: Bool
        let findings: [Finding]
    }
}

extension SnapshotWriter.Snapshot {
    /// Builds a snapshot from the engine's current values.
    ///
    /// Only reads what is sampled on every tick, so the file never contains a
    /// figure that is stale because a window happens to be closed. Per-domain
    /// watts and the extended sensors are absent for that reason, the same
    /// boundary the Shortcuts actions draw.
    @MainActor
    init(engine: MetricsEngine) {
        let findings = SystemVerdict.evaluate(engine.verdictInput)
        self.init(
            // Bumped only if a field changes meaning or disappears, so a script
            // can tell a format it understands from one it does not.
            schema: 1,
            timestamp: Date(),
            cpuPercent: engine.cpuUsagePercent,
            memoryUsedGB: engine.memoryUsedGB,
            memoryTotalGB: engine.memoryTotalGB,
            memoryPercent: engine.memoryTotalGB > 0
                ? engine.memoryUsedGB / engine.memoryTotalGB * 100 : 0,
            swapUsedGB: engine.swapUsedGB,
            memoryPressure: {
                switch engine.memoryPressureLevel {
                case 4:  return "critical"
                case 2:  return "warning"
                default: return "normal"
                }
            }(),
            diskFreeGB: engine.diskFreeGB,
            diskTotalGB: engine.diskTotalGB,
            downloadKBps: engine.downloadSpeedKBps,
            uploadKBps: engine.uploadSpeedKBps,
            cpuTemperatureC: engine.cpuTemperatureC,
            gpuTemperatureC: engine.gpuTemperatureC,
            thermalState: {
                switch engine.thermalState {
                case .critical: return "critical"
                case .serious:  return "serious"
                case .fair:     return "fair"
                default:        return "nominal"
                }
            }(),
            batteryPercent: engine.batteryPercent,
            batteryCharging: engine.batteryIsCharging,
            findings: findings.map {
                Finding(topic: $0.topic.rawValue,
                        severity: String(describing: $0.severity),
                        // In whatever language the app is set to: the file is
                        // read by the person who turned it on, not by a service.
                        message: FindingWording.sentence(for: $0.kind),
                        advice: FindingWording.advice(for: $0.kind))
            }
        )
    }
}
