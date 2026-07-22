import Foundation

/// One calendar day's total network usage, as persisted by `DataUsageStore`.
public struct DailyDataUsage: Equatable, Sendable {
    /// Start-of-day (midnight, local calendar) the totals belong to.
    public let day: Date
    public let downloadBytes: UInt64
    public let uploadBytes: UInt64

    public init(day: Date, downloadBytes: UInt64, uploadBytes: UInt64) {
        self.day = day
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
    }
}

/// Summed download/upload totals for a period.
public struct DataUsageTotals: Equatable, Sendable {
    public let downloadBytes: UInt64
    public let uploadBytes: UInt64

    public static let zero = DataUsageTotals(downloadBytes: 0, uploadBytes: 0)

    public init(downloadBytes: UInt64, uploadBytes: UInt64) {
        self.downloadBytes = downloadBytes
        self.uploadBytes = uploadBytes
    }
}

/// Pure aggregation over persisted per-day usage rows — no I/O. The store
/// loads rows from disk and hands the array here; empty input (no history
/// yet) safely yields `.zero` rather than trapping or returning nil.
public enum DataUsageAggregation {
    public static func today(_ days: [DailyDataUsage], now: Date, calendar: Calendar = .current) -> DataUsageTotals {
        sum(days.filter { calendar.isDate($0.day, inSameDayAs: now) })
    }

    /// Calendar week (respecting the calendar's first weekday), not a
    /// rolling 7-day window.
    public static func thisWeek(_ days: [DailyDataUsage], now: Date, calendar: Calendar = .current) -> DataUsageTotals {
        sum(days.filter { calendar.isDate($0.day, equalTo: now, toGranularity: .weekOfYear) })
    }

    public static func thisMonth(_ days: [DailyDataUsage], now: Date, calendar: Calendar = .current) -> DataUsageTotals {
        sum(days.filter { calendar.isDate($0.day, equalTo: now, toGranularity: .month) })
    }

    /// Rolling window covering `now`'s day and the `count - 1` days before
    /// it (e.g. `count: 7` → today plus the six prior days) — unlike
    /// `thisWeek`, which follows the calendar week regardless of where
    /// `now` falls in it. Used by the "This Week" weekly-overview card,
    /// which aligns with the history window's own rolling 7-day period.
    public static func lastNDays(_ days: [DailyDataUsage], count: Int, now: Date, calendar: Calendar = .current) -> DataUsageTotals {
        guard count > 0 else { return .zero }
        let startOfToday = calendar.startOfDay(for: now)
        guard let cutoff = calendar.date(byAdding: .day, value: -(count - 1), to: startOfToday) else { return .zero }
        return sum(days.filter { $0.day >= cutoff && $0.day <= startOfToday })
    }

    private static func sum(_ days: [DailyDataUsage]) -> DataUsageTotals {
        var down: UInt64 = 0
        var up: UInt64 = 0
        for day in days {
            down += day.downloadBytes
            up += day.uploadBytes
        }
        return DataUsageTotals(downloadBytes: down, uploadBytes: up)
    }
}
