import AppKit
import Foundation
import PerformanceAppCore

/// Owns the on-disk day-granularity data-usage file: cumulative physical-
/// interface byte counters (from `NetworkSampler`) are turned into daily
/// download/upload totals via `DataUsageDelta`, persisted to
/// `data_usage.csv` in the app-support directory, and exposed for
/// aggregation via `DataUsageAggregation`. Follows the same on-disk
/// location/lazy-directory pattern as `HistoryStore`.
///
/// Measurement starts the moment this store first runs — there is no
/// historical data before that, hence `trackingStartDate`.
@MainActor
final class DataUsageStore: ObservableObject {

    private let fileURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PerformanceApp", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("data_usage.csv")
    }()

    /// Per-day totals, keyed by start-of-day. Loaded from disk at launch and
    /// rewritten (a tiny file — one row per day) whenever a day's totals
    /// change.
    @Published private(set) var dailyUsage: [DailyDataUsage] = []

    /// The earliest day usage was ever recorded on this machine — shown in
    /// the UI as "Tracking since <date>" since there's no data before it.
    /// `nil` until the first sample lands.
    var trackingStartDate: Date? { dailyUsage.map(\.day).min() }

    /// Cumulative physical-interface counters from the previous sample.
    /// `nil` right after launch (or reset) — the first sample only
    /// establishes this baseline. Interface counters run since boot/link-up,
    /// so treating that very first reading as "today's usage" would
    /// massively over-count.
    private var previousCumulative: (down: UInt64, up: UInt64)?
    private let calendar = Calendar.current

    /// Disk-write throttle. The in-memory `dailyUsage` is always current (and
    /// drives the live UI); the CSV is a tiny durability backstop that only
    /// needs to survive a quit or crash. Rewriting it every network tick meant
    /// an atomic file write every second at idle — pure wasted I/O. Instead we
    /// coalesce writes to at most once per minute and flush on clean quit.
    private var lastDiskWrite: Date = .distantPast
    private var pendingWrite = false
    private let minWriteInterval: TimeInterval = 60

    init() {
        load()
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.flushIfPending() }
        }
    }

    /// Feeds one sample's cumulative physical-interface byte counters into
    /// the store. Called every network sample tick from `MetricsEngine`.
    func record(physicalBytesReceived: UInt64, physicalBytesSent: UInt64, now: Date = Date()) {
        defer { previousCumulative = (physicalBytesReceived, physicalBytesSent) }
        guard let prev = previousCumulative else { return }

        let deltaDown = DataUsageDelta.delta(previous: prev.down, current: physicalBytesReceived)
        let deltaUp = DataUsageDelta.delta(previous: prev.up, current: physicalBytesSent)
        guard deltaDown > 0 || deltaUp > 0 else { return }

        let day = calendar.startOfDay(for: now)
        if let idx = dailyUsage.firstIndex(where: { $0.day == day }) {
            let existing = dailyUsage[idx]
            dailyUsage[idx] = DailyDataUsage(day: day,
                                              downloadBytes: existing.downloadBytes + deltaDown,
                                              uploadBytes: existing.uploadBytes + deltaUp)
        } else {
            dailyUsage.append(DailyDataUsage(day: day, downloadBytes: deltaDown, uploadBytes: deltaUp))
        }
        scheduleSave(now: now)
    }

    /// Persists at most once per `minWriteInterval`; between writes the newest
    /// totals live in memory (and drive the UI) and are marked pending so a
    /// later tick or the terminate flush commits them.
    private func scheduleSave(now: Date) {
        if now.timeIntervalSince(lastDiskWrite) >= minWriteInterval {
            save()
            lastDiskWrite = now
            pendingWrite = false
        } else {
            pendingWrite = true
        }
    }

    private func flushIfPending() {
        guard pendingWrite else { return }
        save()
        lastDiskWrite = Date()
        pendingWrite = false
    }

    /// Clears all recorded history and removes the on-disk file. The next
    /// `record` call re-establishes a fresh baseline rather than computing a
    /// delta against pre-reset counters.
    func reset() {
        dailyUsage = []
        previousCumulative = nil
        pendingWrite = false
        lastDiskWrite = .distantPast
        try? FileManager.default.removeItem(at: fileURL)
    }

    // MARK: - Persistence

    private func load() {
        guard let contents = try? String(contentsOf: fileURL, encoding: .utf8) else { return }
        var rows: [DailyDataUsage] = []
        for line in contents.split(separator: "\n").dropFirst() {  // skip header
            let fields = line.split(separator: ",")
            guard fields.count == 3,
                  let dayValue = TimeInterval(fields[0]),
                  let down = UInt64(fields[1]),
                  let up = UInt64(fields[2]) else { continue }
            rows.append(DailyDataUsage(day: Date(timeIntervalSince1970: dayValue), downloadBytes: down, uploadBytes: up))
        }
        dailyUsage = rows
    }

    private func save() {
        var csv = "day,download_bytes,upload_bytes\n"
        for row in dailyUsage.sorted(by: { $0.day < $1.day }) {
            csv += "\(row.day.timeIntervalSince1970),\(row.downloadBytes),\(row.uploadBytes)\n"
        }
        try? csv.write(to: fileURL, atomically: true, encoding: .utf8)
    }
}
