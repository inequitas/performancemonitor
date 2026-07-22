import Testing
@testable import PerformanceAppCore

@Suite("DataUsageDelta")
struct DataUsageDeltaTests {

    @Test func normalIncreaseProducesPositiveDelta() {
        #expect(DataUsageDelta.delta(previous: 1_000, current: 1_500) == 500)
    }

    @Test func noChangeProducesZeroDelta() {
        #expect(DataUsageDelta.delta(previous: 1_000, current: 1_000) == 0)
    }

    @Test func counterResetToZeroCountsFromZero() {
        // Interface restarted / machine rebooted: counter dropped below the
        // previous reading. We should attribute `current` bytes (transferred
        // since the reset), not a negative or wrapped-around delta.
        #expect(DataUsageDelta.delta(previous: 50_000, current: 0) == 0)
    }

    @Test func counterResetToNonZeroCountsFromZero() {
        // Reset happened, then some traffic flowed before this sample.
        #expect(DataUsageDelta.delta(previous: 50_000, current: 200) == 200)
    }

    @Test func firstSampleAfterLaunchHasNoPriorBaseline() {
        // previous == current == 0 is the degenerate "just started" case.
        #expect(DataUsageDelta.delta(previous: 0, current: 0) == 0)
    }

    @Test func largeCumulativeValuesDoNotOverflow() {
        let big: UInt64 = .max - 100
        #expect(DataUsageDelta.delta(previous: big, current: .max) == 100)
    }

    @Test func interfaceSwapWithSmallerButNonZeroCounterIsTreatedAsReset() {
        // e.g. switching from a long-lived Wi-Fi session to a freshly
        // attached Ethernet cable — the new interface's counter starts low
        // relative to the old accumulated total.
        #expect(DataUsageDelta.delta(previous: 9_000_000, current: 3_000) == 3_000)
    }
}
