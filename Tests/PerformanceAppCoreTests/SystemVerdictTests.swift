import Testing
@testable import PerformanceAppCore

@Suite("SystemVerdict")
struct SystemVerdictTests {

    /// A machine with nothing wrong with it. Individual tests push one value.
    private func calm(
        cpu: Double = 12,
        usedGB: Double = 8,
        totalGB: Double = 32,
        swapGB: Double = 0,
        diskFreeGB: Double = 400,
        thermal: Int = 0,
        top: (name: String, percent: Double)? = nil
    ) -> SystemVerdict.Input {
        SystemVerdict.Input(cpuPercent: cpu, memoryUsedGB: usedGB, memoryTotalGB: totalGB,
                            swapUsedGB: swapGB, diskFreeGB: diskFreeGB,
                            thermalLevel: thermal, topProcess: top)
    }

    @Test func quietMachineSaysNothingIsWrong() {
        #expect(SystemVerdict.evaluate(calm()) == .allQuiet)
        #expect(SystemVerdict.evaluate(calm()).isNoteworthy == false)
    }

    @Test func seriousThermalPressureThrottles() {
        #expect(SystemVerdict.evaluate(calm(thermal: 2)) == .throttling(serious: false))
        #expect(SystemVerdict.evaluate(calm(thermal: 3)) == .throttling(serious: true))
    }

    @Test func fairThermalPressureIsNotWorthMentioning() {
        // macOS reports "fair" routinely under ordinary load. Saying something
        // every time would train the reader to ignore the line.
        #expect(SystemVerdict.evaluate(calm(thermal: 1)) == .allQuiet)
    }

    @Test func throttlingOutranksEverythingElse() {
        let bad = calm(cpu: 99, usedGB: 31, swapGB: 8, diskFreeGB: 1, thermal: 3,
                       top: ("swift-frontend", 95))
        #expect(SystemVerdict.evaluate(bad) == .throttling(serious: true))
    }

    @Test func swapOutranksCPUAndMemory() {
        let v = SystemVerdict.evaluate(calm(cpu: 99, usedGB: 31, swapGB: 6))
        #expect(v == .swapping(gb: 6))
    }

    @Test func smallSwapIsNotReported() {
        // macOS keeps a little swap around even when memory is plentiful.
        #expect(SystemVerdict.evaluate(calm(swapGB: 1.2)) == .allQuiet)
    }

    @Test func dominantProcessIsNamed() {
        let v = SystemVerdict.evaluate(calm(cpu: 90, top: ("swift-frontend", 82)))
        #expect(v == .busyProcess(name: "swift-frontend", percent: 82))
    }

    @Test func busyWithoutOneCulpritDoesNotBlameTheTopProcess() {
        // Everything is busy but nothing dominates: naming whatever happens to
        // sort first would be misleading.
        let v = SystemVerdict.evaluate(calm(cpu: 90, top: ("WindowServer", 12)))
        #expect(v == .busy(percent: 90))
    }

    @Test func busyWithNoProcessListStillReports() {
        #expect(SystemVerdict.evaluate(calm(cpu: 88, top: nil)) == .busy(percent: 88))
    }

    @Test func tightMemoryIsReportedAsAPercentage() {
        let v = SystemVerdict.evaluate(calm(usedGB: 29, totalGB: 32))
        guard case let .memoryTight(percent) = v else { Issue.record("expected memoryTight"); return }
        #expect((percent - 90.625).magnitude < 0.001)
    }

    @Test func zeroTotalMemoryDoesNotDivideByZero() {
        // Defensive: a sampler that has not produced a reading yet.
        #expect(SystemVerdict.evaluate(calm(usedGB: 0, totalGB: 0)) == .allQuiet)
    }

    @Test func diskAlmostFullIsTheLastThingChecked() {
        #expect(SystemVerdict.evaluate(calm(diskFreeGB: 4)) == .diskAlmostFull(freeGB: 4))
        // But it loses to anything more urgent.
        #expect(SystemVerdict.evaluate(calm(swapGB: 5, diskFreeGB: 4)) == .swapping(gb: 5))
    }

    @Test func unknownDiskFreeIsNotTreatedAsFull() {
        // 0 GB free means "not measured yet", not "no space left".
        #expect(SystemVerdict.evaluate(calm(diskFreeGB: 0)) == .allQuiet)
    }

    @Test func thresholdsAreInclusive() {
        #expect(SystemVerdict.evaluate(calm(cpu: 80)) == .busy(percent: 80))
        #expect(SystemVerdict.evaluate(calm(swapGB: 2)) == .swapping(gb: 2))
    }
}
