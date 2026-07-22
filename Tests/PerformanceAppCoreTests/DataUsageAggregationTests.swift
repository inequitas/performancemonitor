import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("DataUsageAggregation")
struct DataUsageAggregationTests {

    // Fixed UTC Gregorian calendar so the tests are deterministic regardless
    // of the machine's locale/timezone. Monday-first week to match ISO/most
    // locales' "calendar week" expectations.
    private static var calendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 2 // Monday
        return cal
    }()

    private func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Self.calendar.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func emptyHistoryYieldsZeroForAllPeriods() {
        let now = day(2026, 7, 22)
        #expect(DataUsageAggregation.today([], now: now, calendar: Self.calendar) == .zero)
        #expect(DataUsageAggregation.thisWeek([], now: now, calendar: Self.calendar) == .zero)
        #expect(DataUsageAggregation.thisMonth([], now: now, calendar: Self.calendar) == .zero)
    }

    @Test func todaySumsOnlyMatchingDay() {
        let now = day(2026, 7, 22) // Wednesday
        let rows = [
            DailyDataUsage(day: day(2026, 7, 22), downloadBytes: 100, uploadBytes: 10),
            DailyDataUsage(day: day(2026, 7, 21), downloadBytes: 999, uploadBytes: 999),
        ]
        let totals = DataUsageAggregation.today(rows, now: now, calendar: Self.calendar)
        #expect(totals.downloadBytes == 100)
        #expect(totals.uploadBytes == 10)
    }

    @Test func thisWeekSumsAcrossTheCalendarWeekOnly() {
        // Week of Mon 2026-07-20 .. Sun 2026-07-26.
        let now = day(2026, 7, 22) // Wednesday, same week
        let rows = [
            DailyDataUsage(day: day(2026, 7, 20), downloadBytes: 100, uploadBytes: 1), // Monday, in-week
            DailyDataUsage(day: day(2026, 7, 22), downloadBytes: 200, uploadBytes: 2), // today, in-week
            DailyDataUsage(day: day(2026, 7, 26), downloadBytes: 300, uploadBytes: 3), // Sunday, in-week
            DailyDataUsage(day: day(2026, 7, 19), downloadBytes: 5_000, uploadBytes: 5_000), // prior Sunday, out
            DailyDataUsage(day: day(2026, 7, 27), downloadBytes: 5_000, uploadBytes: 5_000), // next Monday, out
        ]
        let totals = DataUsageAggregation.thisWeek(rows, now: now, calendar: Self.calendar)
        #expect(totals.downloadBytes == 600)
        #expect(totals.uploadBytes == 6)
    }

    @Test func thisWeekAcrossYearBoundaryUsesYearForWeekOfYear() {
        // Week spanning Dec 2026 -> Jan 2027 should not be conflated with the
        // same weekOfYear number a year apart.
        let now = day(2026, 12, 30) // Wednesday, in the week of 2026-12-28..2027-01-03
        let rows = [
            DailyDataUsage(day: day(2026, 12, 28), downloadBytes: 50, uploadBytes: 5), // Monday same week
            DailyDataUsage(day: day(2027, 1, 1), downloadBytes: 70, uploadBytes: 7),   // Friday same week, next year
            DailyDataUsage(day: day(2025, 12, 30), downloadBytes: 9_999, uploadBytes: 9_999), // same weekOfYear number, different year
        ]
        let totals = DataUsageAggregation.thisWeek(rows, now: now, calendar: Self.calendar)
        #expect(totals.downloadBytes == 120)
        #expect(totals.uploadBytes == 12)
    }

    @Test func thisMonthSumsAcrossTheCalendarMonthOnly() {
        let now = day(2026, 7, 15)
        let rows = [
            DailyDataUsage(day: day(2026, 7, 1), downloadBytes: 10, uploadBytes: 1),
            DailyDataUsage(day: day(2026, 7, 31), downloadBytes: 20, uploadBytes: 2),
            DailyDataUsage(day: day(2026, 6, 30), downloadBytes: 9_999, uploadBytes: 9_999), // previous month
            DailyDataUsage(day: day(2026, 8, 1), downloadBytes: 9_999, uploadBytes: 9_999),  // next month
        ]
        let totals = DataUsageAggregation.thisMonth(rows, now: now, calendar: Self.calendar)
        #expect(totals.downloadBytes == 30)
        #expect(totals.uploadBytes == 3)
    }

    @Test func totalsZeroConstantIsAllZero() {
        #expect(DataUsageTotals.zero.downloadBytes == 0)
        #expect(DataUsageTotals.zero.uploadBytes == 0)
    }

    // MARK: - lastNDays

    @Test func lastNDaysOnEmptyHistoryYieldsZero() {
        #expect(DataUsageAggregation.lastNDays([], count: 7, now: day(2026, 7, 22), calendar: Self.calendar) == .zero)
    }

    @Test func lastNDaysIsARollingWindowNotACalendarWeek() {
        // now: Wed 2026-07-22 -> last 7 days = Thu 07-16 .. Wed 07-22,
        // which straddles two different calendar weeks.
        let now = day(2026, 7, 22)
        let rows = [
            DailyDataUsage(day: day(2026, 7, 16), downloadBytes: 1, uploadBytes: 1), // 7 days ago, in-window (prior cal week)
            DailyDataUsage(day: day(2026, 7, 22), downloadBytes: 2, uploadBytes: 2), // today, in-window
            DailyDataUsage(day: day(2026, 7, 15), downloadBytes: 9_999, uploadBytes: 9_999), // 8 days ago, out
            DailyDataUsage(day: day(2026, 7, 23), downloadBytes: 9_999, uploadBytes: 9_999), // tomorrow, out
        ]
        let totals = DataUsageAggregation.lastNDays(rows, count: 7, now: now, calendar: Self.calendar)
        #expect(totals.downloadBytes == 3)
        #expect(totals.uploadBytes == 3)
    }

    @Test func lastNDaysWithCountOneIsJustToday() {
        let now = day(2026, 7, 22)
        let rows = [
            DailyDataUsage(day: day(2026, 7, 22), downloadBytes: 5, uploadBytes: 5),
            DailyDataUsage(day: day(2026, 7, 21), downloadBytes: 9_999, uploadBytes: 9_999),
        ]
        let totals = DataUsageAggregation.lastNDays(rows, count: 1, now: now, calendar: Self.calendar)
        #expect(totals.downloadBytes == 5)
        #expect(totals.uploadBytes == 5)
    }
}
