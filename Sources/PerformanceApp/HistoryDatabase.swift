import Foundation
import SQLite3
import PerformanceAppCore

/// Long-running, tiered on-disk history store backed by SQLite
/// (`~/Library/Application Support/PerformanceApp/history.sqlite`). Sits
/// alongside the older `HistoryStore` CSV (unchanged, still opt-in via the
/// same `persistHistoryEnabled` preference) rather than replacing it — this
/// store is what the roadmap-1.3a history window (part 2) will query.
///
/// Runs on its own actor so SQLite I/O (recording every tick, periodic
/// compaction) never touches the main thread. All tier/bucket/retention
/// *decisions* live in `HistoryRetention` (PerformanceAppCore — pure,
/// DB-independent, unit-tested); this type only does I/O and calls that
/// logic. Three tables mirror the three `HistoryTier` cases: `raw_samples`
/// (1s rows, ~1h retention), `minute_samples` and `hour_samples` (min/avg/max
/// rows, ~48h and ~90d retention respectively).
actor HistoryDatabase {

    private let fileURL: URL
    private var db: OpaquePointer?
    private var lastRecordedAt: Date?

    /// Minimum spacing between recorded samples regardless of call
    /// frequency — the engine's refresh interval can go as low as 0.5s, but
    /// raw history is only meaningful at 1s resolution.
    private let minRecordSpacing: TimeInterval = 1.0

    /// `fileURL` is injectable for tests; production callers use the default
    /// (creates `Application Support/PerformanceApp` if needed).
    ///
    /// Opening + schema setup is done with a `static` helper rather than an
    /// instance method: actor-isolated instance methods can't be called
    /// synchronously from within `init` (the instance isn't fully formed
    /// yet), so this only ever touches a local `OpaquePointer?`, then
    /// assigns the result to `self.db` once, which `init` is always allowed
    /// to do.
    init(fileURL: URL? = nil) {
        let url: URL
        if let fileURL {
            url = fileURL
        } else {
            let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("PerformanceApp", isDirectory: true)
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            url = dir.appendingPathComponent("history.sqlite")
        }
        self.fileURL = url
        self.db = HistoryDatabase.openAndConfigure(at: url)
    }

    deinit {
        if let db { sqlite3_close(db) }
    }

    // MARK: - Setup

    private static func openAndConfigure(at url: URL) -> OpaquePointer? {
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle,
                               SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK else {
            return nil
        }
        sqlite3_exec(handle, "PRAGMA journal_mode=WAL;", nil, nil, nil)
        sqlite3_exec(handle, "PRAGMA synchronous=NORMAL;", nil, nil, nil)
        sqlite3_exec(handle, """
            CREATE TABLE IF NOT EXISTS raw_samples (
                metric TEXT NOT NULL,
                ts REAL NOT NULL,
                value REAL NOT NULL
            );
            """, nil, nil, nil)
        sqlite3_exec(handle, "CREATE INDEX IF NOT EXISTS idx_raw_metric_ts ON raw_samples(metric, ts);", nil, nil, nil)
        for table in ["minute_samples", "hour_samples"] {
            sqlite3_exec(handle, """
                CREATE TABLE IF NOT EXISTS \(table) (
                    metric TEXT NOT NULL,
                    bucket_start REAL NOT NULL,
                    min_value REAL NOT NULL,
                    avg_value REAL NOT NULL,
                    max_value REAL NOT NULL,
                    PRIMARY KEY (metric, bucket_start)
                );
                """, nil, nil, nil)
            sqlite3_exec(handle, "CREATE INDEX IF NOT EXISTS idx_\(table)_metric_ts ON \(table)(metric, bucket_start);", nil, nil, nil)
        }
        return handle
    }

    private func exec(_ sql: String) {
        guard let db else { return }
        sqlite3_exec(db, sql, nil, nil, nil)
    }

    /// Closes the underlying SQLite handle early. Production instances live
    /// for the app's lifetime and rely on process exit; this exists for
    /// tests that need a clean shutdown before inspecting the file.
    func close() {
        if let db { sqlite3_close(db) }
        db = nil
    }

    // MARK: - Recording

    /// Records one tick's worth of readings, throttled to at most once per
    /// `minRecordSpacing`. No-ops silently if the database failed to open —
    /// callers are expected to already gate this on `persistHistoryEnabled`.
    func record(_ values: [HistoryMetric: Double], at date: Date = Date()) {
        guard let db else { return }
        if let last = lastRecordedAt, date.timeIntervalSince(last) < minRecordSpacing { return }
        lastRecordedAt = date

        let sql = "INSERT INTO raw_samples (metric, ts, value) VALUES (?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        exec("BEGIN IMMEDIATE;")
        for (metric, value) in values {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, date.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, value)
            sqlite3_step(stmt)
        }
        exec("COMMIT;")
    }

    // MARK: - Compaction

    /// Rolls closed raw buckets up into minute aggregates, closed minute
    /// buckets up into hour aggregates, and prunes rows that have fallen out
    /// of each tier's retention window. Safe to call repeatedly — upserts
    /// are idempotent. Intended to run roughly once a minute from a
    /// background task, never on the main thread.
    func compact(now: Date = Date()) {
        guard db != nil else { return }
        for metric in HistoryMetric.allCases {
            compactRawToMinute(metric: metric, now: now)
            compactMinuteToHour(metric: metric, now: now)
        }
        prune(now: now)
    }

    private func compactRawToMinute(metric: HistoryMetric, now: Date) {
        let cutoff = HistoryRetention.retentionCutoff(tier: .raw, now: now)
        let raw = fetchRaw(metric: metric, since: cutoff)
        guard !raw.isEmpty else { return }
        let closed = HistoryRetention.aggregate(raw, tier: .minute)
            .filter { HistoryRetention.isBucketClosed(bucketStart: $0.bucketStart, tier: .minute, now: now) }
        upsert(closed, metric: metric, table: "minute_samples")
    }

    private func compactMinuteToHour(metric: HistoryMetric, now: Date) {
        let cutoff = HistoryRetention.retentionCutoff(tier: .minute, now: now)
        let minuteRows = fetchAggregates(table: "minute_samples", metric: metric, since: cutoff)
        guard !minuteRows.isEmpty else { return }
        let closed = HistoryRetention.combine(minuteRows, tier: .hour)
            .filter { HistoryRetention.isBucketClosed(bucketStart: $0.bucketStart, tier: .hour, now: now) }
        upsert(closed, metric: metric, table: "hour_samples")
    }

    private func prune(now: Date) {
        run("DELETE FROM raw_samples WHERE ts < ?;",
            HistoryRetention.retentionCutoff(tier: .raw, now: now).timeIntervalSince1970)
        run("DELETE FROM minute_samples WHERE bucket_start < ?;",
            HistoryRetention.retentionCutoff(tier: .minute, now: now).timeIntervalSince1970)
        run("DELETE FROM hour_samples WHERE bucket_start < ?;",
            HistoryRetention.retentionCutoff(tier: .hour, now: now).timeIntervalSince1970)
    }

    private func run(_ sql: String, _ cutoff: Double) {
        guard let db else { return }
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_double(stmt, 1, cutoff)
        sqlite3_step(stmt)
    }

    private func upsert(_ aggregates: [HistoryAggregate], metric: HistoryMetric, table: String) {
        guard let db, !aggregates.isEmpty else { return }
        let sql = "INSERT OR REPLACE INTO \(table) (metric, bucket_start, min_value, avg_value, max_value) VALUES (?, ?, ?, ?, ?);"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return }
        defer { sqlite3_finalize(stmt) }

        exec("BEGIN IMMEDIATE;")
        for a in aggregates {
            sqlite3_reset(stmt)
            sqlite3_clear_bindings(stmt)
            sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
            sqlite3_bind_double(stmt, 2, a.bucketStart.timeIntervalSince1970)
            sqlite3_bind_double(stmt, 3, a.min)
            sqlite3_bind_double(stmt, 4, a.avg)
            sqlite3_bind_double(stmt, 5, a.max)
            sqlite3_step(stmt)
        }
        exec("COMMIT;")
    }

    // MARK: - Fetch helpers

    private func fetchRaw(metric: HistoryMetric, since: Date) -> [HistorySample] {
        guard let db else { return [] }
        let sql = "SELECT ts, value FROM raw_samples WHERE metric = ? AND ts >= ? ORDER BY ts;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, since.timeIntervalSince1970)

        var result: [HistorySample] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            let ts = sqlite3_column_double(stmt, 0)
            let value = sqlite3_column_double(stmt, 1)
            result.append(HistorySample(date: Date(timeIntervalSince1970: ts), value: value))
        }
        return result
    }

    private func fetchAggregates(table: String, metric: HistoryMetric, since: Date) -> [HistoryAggregate] {
        guard let db else { return [] }
        let sql = "SELECT bucket_start, min_value, avg_value, max_value FROM \(table) WHERE metric = ? AND bucket_start >= ? ORDER BY bucket_start;"
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(stmt) }
        sqlite3_bind_text(stmt, 1, metric.rawValue, -1, SQLITE_TRANSIENT)
        sqlite3_bind_double(stmt, 2, since.timeIntervalSince1970)

        var result: [HistoryAggregate] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            result.append(HistoryAggregate(
                bucketStart: Date(timeIntervalSince1970: sqlite3_column_double(stmt, 0)),
                min: sqlite3_column_double(stmt, 1),
                avg: sqlite3_column_double(stmt, 2),
                max: sqlite3_column_double(stmt, 3)))
        }
        return result
    }

    // MARK: - Query API (for the history-window UI — roadmap 1.3a, part 2)

    /// Returns `(bucketStart, min, avg, max)` rows covering `from...to`,
    /// automatically reading from whichever tier `HistoryRetention.queryTier`
    /// selects for that span. Raw rows are reported as `(date, value, value,
    /// value)` since there's nothing to aggregate at that resolution.
    func samples(metric: HistoryMetric, from: Date, to: Date) -> [(date: Date, min: Double, avg: Double, max: Double)] {
        guard db != nil else { return [] }
        switch HistoryRetention.queryTier(from: from, to: to) {
        case .raw:
            return fetchRaw(metric: metric, since: from)
                .filter { $0.date <= to }
                .map { (date: $0.date, min: $0.value, avg: $0.value, max: $0.value) }
        case .minute:
            return fetchAggregates(table: "minute_samples", metric: metric, since: from)
                .filter { $0.bucketStart <= to }
                .map { (date: $0.bucketStart, min: $0.min, avg: $0.avg, max: $0.max) }
        case .hour:
            return fetchAggregates(table: "hour_samples", metric: metric, since: from)
                .filter { $0.bucketStart <= to }
                .map { (date: $0.bucketStart, min: $0.min, avg: $0.avg, max: $0.max) }
        }
    }
}

/// `SQLITE_TRANSIENT` is a C macro (`(sqlite3_destructor_type)-1`), not
/// imported into Swift automatically — this is the standard workaround so
/// bound text values are copied by SQLite rather than referencing a Swift
/// string buffer that may already be gone by the time the statement runs.
private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
