import Foundation

/// Average/peak summary for one history metric over the "This Week" overview
/// window (roadmap 1.3b).
public struct WeeklyMetricSummary: Equatable, Sendable {
    public let average: Double
    public let peak: Double
    public let peakAt: Date

    public init(average: Double, peak: Double, peakAt: Date) {
        self.average = average
        self.peak = peak
        self.peakAt = peakAt
    }
}

/// Pure aggregation for the "This Week" overview: condenses a week's worth
/// of already-tiered history rows (as returned by `HistoryDatabase.samples`,
/// shaped like `HistoryAggregate`) into one average/peak line per metric.
/// No I/O — callers fetch rows, this only crunches numbers, so it's
/// independently unit-testable.
public enum WeeklySummary {

    /// `average` is the unweighted mean of each row's own `avg` (matching
    /// `HistoryRetention.combine`'s existing rollup convention); `peak` is
    /// the highest `max` across rows, and `peakAt` that row's bucket start —
    /// a best-effort peak instant rather than necessarily the single highest
    /// raw sample, since rows may already be minute/hour aggregates.
    ///
    /// Returns `nil` for empty input rather than a zeroed struct, so callers
    /// can distinguish "no data this week" from "flat at zero".
    public static func metricSummary(_ rows: [HistoryAggregate]) -> WeeklyMetricSummary? {
        guard !rows.isEmpty else { return nil }
        let average = rows.reduce(0.0) { $0 + $1.avg } / Double(rows.count)
        let peakRow = rows.max { $0.max < $1.max } ?? rows[0]
        return WeeklyMetricSummary(average: average, peak: peakRow.max, peakAt: peakRow.bucketStart)
    }
}
