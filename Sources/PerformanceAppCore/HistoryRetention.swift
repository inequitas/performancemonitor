import Foundation

/// Identifies one of the metrics persisted to the tiered on-disk history
/// database (`HistoryDatabase`, Sources/PerformanceApp). Raw values double
/// as the SQLite `metric` column value — do not rename existing cases
/// without a migration.
public enum HistoryMetric: String, CaseIterable, Sendable {
    case cpuUsagePercent
    case memoryUsedPercent
    case gpuUsagePercent
    case downloadSpeedKBps
    case uploadSpeedKBps
    case diskReadKBps
    case diskWriteKBps
}

/// One resolution tier of the tiered history store: recent data is kept at
/// full 1s resolution, older data is progressively downsampled so on-disk
/// size stays bounded no matter how long the app has been recording.
public enum HistoryTier: String, CaseIterable, Sendable {
    case raw
    case minute
    case hour

    /// Width of one bucket at this tier, in seconds.
    public var bucketDuration: TimeInterval {
        switch self {
        case .raw:    return 1
        case .minute: return 60
        case .hour:   return 3600
        }
    }

    /// How far back rows at this tier are retained before being pruned.
    public var retention: TimeInterval {
        switch self {
        case .raw:    return 3_600        // ~1 hour
        case .minute: return 48 * 3_600   // ~48 hours
        case .hour:   return 90 * 86_400  // ~90 days
        }
    }
}

/// A single timestamped reading, as recorded every tick.
public struct HistorySample: Sendable {
    public let date: Date
    public let value: Double

    public init(date: Date, value: Double) {
        self.date = date
        self.value = value
    }
}

/// A min/avg/max summary for one bucket.
public struct HistoryAggregate: Equatable, Sendable {
    public let bucketStart: Date
    public let min: Double
    public let avg: Double
    public let max: Double

    public init(bucketStart: Date, min: Double, avg: Double, max: Double) {
        self.bucketStart = bucketStart
        self.min = min
        self.avg = avg
        self.max = max
    }
}

/// Pure decision logic for the tiered history store: bucket boundaries,
/// aggregation, retention pruning, and query-tier selection. No I/O — the
/// SQLite-backed `HistoryDatabase` is the only caller and owns all
/// persistence; everything here is deterministic and independently
/// unit-testable.
public enum HistoryRetention {

    /// Floors `date` to the start of its bucket for `tier`, aligned to the
    /// Unix epoch so bucket boundaries are stable across process restarts.
    public static func bucketStart(for date: Date, tier: HistoryTier) -> Date {
        let duration = tier.bucketDuration
        let epoch = date.timeIntervalSince1970
        let floored = (epoch / duration).rounded(.down) * duration
        return Date(timeIntervalSince1970: floored)
    }

    /// True once `now` has moved past the end of the bucket starting at
    /// `bucketStart` — i.e. it's safe to summarize (no further samples will
    /// ever land in it).
    public static func isBucketClosed(bucketStart: Date, tier: HistoryTier, now: Date) -> Bool {
        bucketStart.addingTimeInterval(tier.bucketDuration) <= now
    }

    /// Groups raw samples into `tier`-sized buckets and computes min/avg/max
    /// per bucket. Input need not be sorted. Empty input yields `[]`.
    public static func aggregate(_ samples: [HistorySample], tier: HistoryTier) -> [HistoryAggregate] {
        guard !samples.isEmpty else { return [] }
        var buckets: [Date: [Double]] = [:]
        for sample in samples {
            buckets[bucketStart(for: sample.date, tier: tier), default: []].append(sample.value)
        }
        return buckets.map { start, values in
            HistoryAggregate(bucketStart: start,
                              min: values.min() ?? 0,
                              avg: values.reduce(0, +) / Double(values.count),
                              max: values.max() ?? 0)
        }.sorted { $0.bucketStart < $1.bucketStart }
    }

    /// Rolls already-summarized rows (e.g. minute aggregates) up into the
    /// next tier (e.g. hour): min-of-mins, max-of-maxes, and an unweighted
    /// average of the sub-bucket averages. That average is a standard, cheap
    /// rollup approximation — exact when every sub-bucket has an equal
    /// sample count, otherwise a close estimate. Empty input yields `[]`.
    public static func combine(_ aggregates: [HistoryAggregate], tier: HistoryTier) -> [HistoryAggregate] {
        guard !aggregates.isEmpty else { return [] }
        var buckets: [Date: [HistoryAggregate]] = [:]
        for aggregate in aggregates {
            buckets[bucketStart(for: aggregate.bucketStart, tier: tier), default: []].append(aggregate)
        }
        return buckets.map { start, group in
            HistoryAggregate(bucketStart: start,
                              min: group.map(\.min).min() ?? 0,
                              avg: group.map(\.avg).reduce(0, +) / Double(group.count),
                              max: group.map(\.max).max() ?? 0)
        }.sorted { $0.bucketStart < $1.bucketStart }
    }

    /// The earliest bucket-start still retained for `tier` as of `now`. Rows
    /// with an older bucket start should be pruned.
    public static func retentionCutoff(tier: HistoryTier, now: Date) -> Date {
        Date(timeIntervalSince1970: now.timeIntervalSince1970 - tier.retention)
    }

    /// Which tier a `samples(from:to:)` query should read from, based purely
    /// on the requested span: the finest tier whose retention window still
    /// comfortably covers the whole span, so callers never hit a gap from a
    /// tier that has already pruned part of the requested range.
    public static func queryTier(from: Date, to: Date) -> HistoryTier {
        let span = to.timeIntervalSince(from)
        if span <= HistoryTier.raw.retention    { return .raw }
        if span <= HistoryTier.minute.retention { return .minute }
        return .hour
    }
}
