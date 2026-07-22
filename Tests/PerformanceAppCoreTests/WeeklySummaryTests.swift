import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("WeeklySummary")
struct WeeklySummaryTests {

    private func date(_ epoch: TimeInterval) -> Date { Date(timeIntervalSince1970: epoch) }

    @Test func emptyWeekYieldsNil() {
        #expect(WeeklySummary.metricSummary([]) == nil)
    }

    @Test func singleDayUsesItsOwnAverageAndPeak() {
        let row = HistoryAggregate(bucketStart: date(1_000), min: 10, avg: 20, max: 30)
        let summary = WeeklySummary.metricSummary([row])
        #expect(summary?.average == 20)
        #expect(summary?.peak == 30)
        #expect(summary?.peakAt == date(1_000))
    }

    @Test func multipleDaysAverageTheAveragesAndTakeTheHighestMax() {
        let rows = [
            HistoryAggregate(bucketStart: date(0), min: 0, avg: 10, max: 40),
            HistoryAggregate(bucketStart: date(86_400), min: 0, avg: 30, max: 20),
            HistoryAggregate(bucketStart: date(172_800), min: 0, avg: 20, max: 90),
        ]
        let summary = WeeklySummary.metricSummary(rows)
        #expect(summary?.average == 20) // (10 + 30 + 20) / 3
        #expect(summary?.peak == 90)
        #expect(summary?.peakAt == date(172_800))
    }

    @Test func peakDetectionPicksTheFirstRowOnATie() {
        let rows = [
            HistoryAggregate(bucketStart: date(0), min: 0, avg: 5, max: 50),
            HistoryAggregate(bucketStart: date(86_400), min: 0, avg: 5, max: 50),
        ]
        let summary = WeeklySummary.metricSummary(rows)
        #expect(summary?.peak == 50)
        #expect(summary?.peakAt == date(0))
    }
}
