import Testing
import Foundation
@testable import PerformanceAppCore

@Suite("HistoryRetention")
struct HistoryRetentionTests {

    private func date(_ epoch: TimeInterval) -> Date { Date(timeIntervalSince1970: epoch) }

    // MARK: - bucketStart

    @Test func bucketStartFloorsRawToTheSecond() {
        let d = date(1_000.75)
        #expect(HistoryRetention.bucketStart(for: d, tier: .raw) == date(1_000))
    }

    @Test func bucketStartFloorsMinuteToSixtySeconds() {
        let d = date(125) // 2m5s
        #expect(HistoryRetention.bucketStart(for: d, tier: .minute) == date(120))
    }

    @Test func bucketStartFloorsHourToThirtySixHundredSeconds() {
        let d = date(3_601) // 1h + 1s
        #expect(HistoryRetention.bucketStart(for: d, tier: .hour) == date(3_600))
    }

    @Test func bucketStartOnExactBoundaryStaysPut() {
        #expect(HistoryRetention.bucketStart(for: date(120), tier: .minute) == date(120))
    }

    // MARK: - isBucketClosed

    @Test func bucketIsOpenWhileNowIsStillInsideIt() {
        #expect(HistoryRetention.isBucketClosed(bucketStart: date(0), tier: .minute, now: date(30)) == false)
    }

    @Test func bucketClosesExactlyAtItsEnd() {
        #expect(HistoryRetention.isBucketClosed(bucketStart: date(0), tier: .minute, now: date(60)) == true)
    }

    @Test func bucketIsClosedWellAfterItEnds() {
        #expect(HistoryRetention.isBucketClosed(bucketStart: date(0), tier: .minute, now: date(999)) == true)
    }

    // MARK: - aggregate

    @Test func aggregateOfEmptyInputIsEmpty() {
        #expect(HistoryRetention.aggregate([], tier: .minute).isEmpty)
    }

    @Test func aggregateComputesMinAvgMaxWithinABucket() {
        let samples = [
            HistorySample(date: date(0), value: 10),
            HistorySample(date: date(20), value: 30),
            HistorySample(date: date(40), value: 20),
        ]
        let result = HistoryRetention.aggregate(samples, tier: .minute)
        #expect(result.count == 1)
        #expect(result[0].bucketStart == date(0))
        #expect(result[0].min == 10)
        #expect(result[0].max == 30)
        #expect(result[0].avg == 20)
    }

    @Test func aggregateSplitsSamplesAcrossBucketBoundaries() {
        let samples = [
            HistorySample(date: date(0), value: 1),
            HistorySample(date: date(59), value: 2),
            HistorySample(date: date(60), value: 100),
            HistorySample(date: date(119), value: 200),
        ]
        let result = HistoryRetention.aggregate(samples, tier: .minute)
        #expect(result.count == 2)
        #expect(result[0].bucketStart == date(0))
        #expect(result[0].min == 1)
        #expect(result[0].max == 2)
        #expect(result[1].bucketStart == date(60))
        #expect(result[1].min == 100)
        #expect(result[1].max == 200)
    }

    @Test func aggregateSortsBucketsByStartRegardlessOfInputOrder() {
        let samples = [
            HistorySample(date: date(120), value: 3),
            HistorySample(date: date(0), value: 1),
            HistorySample(date: date(60), value: 2),
        ]
        let result = HistoryRetention.aggregate(samples, tier: .minute)
        #expect(result.map(\.bucketStart) == [date(0), date(60), date(120)])
    }

    // MARK: - combine

    @Test func combineOfEmptyInputIsEmpty() {
        #expect(HistoryRetention.combine([], tier: .hour).isEmpty)
    }

    @Test func combineRollsUpMinuteAggregatesIntoAnHourBucket() {
        let minutes = [
            HistoryAggregate(bucketStart: date(0), min: 5, avg: 10, max: 15),
            HistoryAggregate(bucketStart: date(60), min: 1, avg: 20, max: 40),
        ]
        let result = HistoryRetention.combine(minutes, tier: .hour)
        #expect(result.count == 1)
        #expect(result[0].bucketStart == date(0))
        #expect(result[0].min == 1)       // min of mins
        #expect(result[0].max == 40)      // max of maxes
        #expect(result[0].avg == 15)      // average of the two averages
    }

    // MARK: - retentionCutoff

    @Test func retentionCutoffForEachTier() {
        let now = date(200_000)
        #expect(HistoryRetention.retentionCutoff(tier: .raw, now: now) == date(200_000 - 3_600))
        #expect(HistoryRetention.retentionCutoff(tier: .minute, now: now) == date(200_000 - 48 * 3_600))
        #expect(HistoryRetention.retentionCutoff(tier: .hour, now: now) == date(200_000 - 90 * 86_400))
    }

    // MARK: - queryTier

    @Test func queryTierUsesRawForSpansUpToOneHour() {
        #expect(HistoryRetention.queryTier(from: date(0), to: date(3_600)) == .raw)
    }

    @Test func queryTierUsesMinuteJustPastOneHour() {
        #expect(HistoryRetention.queryTier(from: date(0), to: date(3_601)) == .minute)
    }

    @Test func queryTierUsesMinuteUpToFortyEightHours() {
        #expect(HistoryRetention.queryTier(from: date(0), to: date(48 * 3_600)) == .minute)
    }

    @Test func queryTierUsesHourPastFortyEightHours() {
        #expect(HistoryRetention.queryTier(from: date(0), to: date(48 * 3_600 + 1)) == .hour)
    }

    @Test func queryTierUsesHourForVeryLongSpans() {
        #expect(HistoryRetention.queryTier(from: date(0), to: date(200 * 86_400)) == .hour)
    }
}
