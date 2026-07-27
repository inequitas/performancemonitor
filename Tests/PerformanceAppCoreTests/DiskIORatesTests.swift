import Testing
@testable import PerformanceAppCore

@Suite("DiskIORates")
struct DiskIORatesTests {

    @Test func computesCombinedReadAndWriteThroughput() {
        let previous: [Int32: DiskIOBytes] = [42: DiskIOBytes(read: 0, written: 0)]
        let current: [Int32: DiskIOBytes] = [42: DiskIOBytes(read: 1024, written: 1024)]
        let names: [Int32: String] = [42: "Xcode"]
        let rows = DiskIORates.rates(current: current, previous: previous,
                                     names: names, previousNames: names,
                                     elapsed: 1, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].pid == 42)
        #expect(rows[0].name == "Xcode")
        #expect(rows[0].value == 2.0)               // (1024+1024)/1/1024 = 2 kB/s
    }

    @Test func variableElapsedIntervalComputesCorrectRate() {
        // The sampler runs on a ~3s throttle, not the 1s engine tick, so the
        // rate must divide by the actual elapsed time.
        let previous: [Int32: DiskIOBytes] = [7: DiskIOBytes(read: 0, written: 0)]
        let current: [Int32: DiskIOBytes] = [7: DiskIOBytes(read: 3072, written: 3072)]
        let rows = DiskIORates.rates(current: current, previous: previous,
                                     names: [7: "Mail"], previousNames: [7: "Mail"],
                                     elapsed: 3, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].value == 2.0)
    }

    @Test func counterResetClampsToZero() {
        // Each direction is clamped independently: read went backwards, write
        // moved 1024 bytes, so only the write delta counts.
        let previous: [Int32: DiskIOBytes] = [9: DiskIOBytes(read: 10_000_000, written: 0)]
        let current: [Int32: DiskIOBytes] = [9: DiskIOBytes(read: 5, written: 1024)]
        let rows = DiskIORates.rates(current: current, previous: previous,
                                     names: [9: "App"], previousNames: [9: "App"],
                                     elapsed: 1, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].value == 1.0)
    }

    @Test func fullCounterResetProducesNoRow() {
        let previous: [Int32: DiskIOBytes] = [9: DiskIOBytes(read: 10_000, written: 10_000)]
        let current: [Int32: DiskIOBytes] = [9: DiskIOBytes(read: 5, written: 5)]
        let rows = DiskIORates.rates(current: current, previous: previous,
                                     names: [9: "App"], previousNames: [9: "App"],
                                     elapsed: 1, topCount: 10)
        #expect(rows.isEmpty)
    }

    @Test func belowThresholdProcessesAreDropped() {
        // 10 bytes over 1s = ~0.0098 kB/s, under the 0.05 kB/s floor.
        let current: [Int32: DiskIOBytes] = [1: DiskIOBytes(read: 10, written: 0)]
        let rows = DiskIORates.rates(current: current, previous: [:],
                                     names: [1: "Quiet"], previousNames: [:],
                                     elapsed: 1, topCount: 10)
        #expect(rows.isEmpty)
    }

    @Test func sortedDescendingAndTruncated() {
        let current: [Int32: DiskIOBytes] = [
            1: DiskIOBytes(read: 100_000, written: 0),
            2: DiskIOBytes(read: 50_000, written: 0),
            3: DiskIOBytes(read: 5_000, written: 0),
        ]
        let names: [Int32: String] = [1: "Big", 2: "Mid", 3: "Small"]
        let rows = DiskIORates.rates(current: current, previous: [:],
                                     names: names, previousNames: [:],
                                     elapsed: 1, topCount: 2)
        #expect(rows.count == 2)
        #expect(rows[0].name == "Big")
        #expect(rows[1].name == "Mid")
    }

    @Test func zeroElapsedYieldsNothing() {
        let current: [Int32: DiskIOBytes] = [1: DiskIOBytes(read: 100_000, written: 0)]
        #expect(DiskIORates.rates(current: current, previous: [:],
                                  names: [1: "App"], previousNames: [:],
                                  elapsed: 0, topCount: 10).isEmpty)
        #expect(DiskIORates.rates(current: current, previous: [:],
                                  names: [1: "App"], previousNames: [:],
                                  elapsed: -1, topCount: 10).isEmpty)
    }

    @Test func missingBaselineTreatedAsZero() {
        // A pid seen for the first time diffs against zero, matching nettop's
        // behaviour: the first reading is the process's lifetime total.
        let current: [Int32: DiskIOBytes] = [55: DiskIOBytes(read: 4096, written: 4096)]
        let rows = DiskIORates.rates(current: current, previous: [:],
                                     names: [55: "New"], previousNames: [:],
                                     elapsed: 1, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].value == 8.0)
    }

    @Test func recycledPidIsSkippedInsteadOfSpiking() {
        // pid 100 used to be "Old" with a low counter; it now belongs to "New"
        // with a large lifetime total. Diffing would report a bogus spike, so
        // the row is skipped this round entirely.
        let previous: [Int32: DiskIOBytes] = [100: DiskIOBytes(read: 10, written: 10)]
        let current: [Int32: DiskIOBytes] = [100: DiskIOBytes(read: 10_000_000, written: 0)]
        let rows = DiskIORates.rates(current: current, previous: previous,
                                     names: [100: "New"], previousNames: [100: "Old"],
                                     elapsed: 1, topCount: 10)
        #expect(rows.isEmpty)
    }

    @Test func recycledPidDoesNotSuppressOtherProcesses() {
        let previous: [Int32: DiskIOBytes] = [
            100: DiskIOBytes(read: 10, written: 10),
            200: DiskIOBytes(read: 0, written: 0),
        ]
        let current: [Int32: DiskIOBytes] = [
            100: DiskIOBytes(read: 10_000_000, written: 0),
            200: DiskIOBytes(read: 2048, written: 0),
        ]
        let rows = DiskIORates.rates(current: current, previous: previous,
                                     names: [100: "New", 200: "Steady"],
                                     previousNames: [100: "Old", 200: "Steady"],
                                     elapsed: 1, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].name == "Steady")
        #expect(rows[0].value == 2.0)
    }

    @Test func unknownNameFallsBackToPidLabel() {
        let current: [Int32: DiskIOBytes] = [321: DiskIOBytes(read: 4096, written: 0)]
        let rows = DiskIORates.rates(current: current, previous: [:],
                                     names: [:], previousNames: [:],
                                     elapsed: 1, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].name == "PID 321")
        #expect(rows[0].id == "321-PID 321")
    }
}
