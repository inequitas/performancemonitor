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
        pressure: Int = 1,
        swapPages: Double = 0,
        diskFreeGB: Double = 400,
        thermal: Int = 0,
        top: (name: String, percent: Double)? = nil
    ) -> SystemVerdict.Input {
        SystemVerdict.Input(cpuPercent: cpu, memoryUsedGB: usedGB, memoryTotalGB: totalGB,
                            swapUsedGB: swapGB,
                            memoryPressureLevel: pressure, swapPagesPerSecond: swapPages,
                            diskFreeGB: diskFreeGB,
                            thermalLevel: thermal, topProcess: top)
    }

    private func kinds(_ input: SystemVerdict.Input) -> [SystemFinding.Kind] {
        SystemVerdict.evaluate(input).map(\.kind)
    }

    @Test func quietMachineFindsNothing() {
        #expect(SystemVerdict.evaluate(calm()).isEmpty)
    }

    @Test func seriousThermalPressureThrottles() {
        #expect(kinds(calm(thermal: 2)) == [.throttling(serious: false)])
        #expect(kinds(calm(thermal: 3)) == [.throttling(serious: true)])
    }

    @Test func fairThermalPressureIsNotWorthMentioning() {
        // macOS reports "fair" routinely under ordinary load. Saying something
        // every time would train the reader to ignore the line.
        #expect(SystemVerdict.evaluate(calm(thermal: 1)).isEmpty)
    }

    @Test func everythingApplicableIsReported() {
        // The whole point of the rework: one urgent finding used to hide the
        // rest, which is what made a lone swap figure hard to interpret.
        let busy = calm(cpu: 95, usedGB: 30, totalGB: 32, swapGB: 6, pressure: 4,
                        diskFreeGB: 3, thermal: 3, top: ("swift-frontend", 90))
        let found = SystemVerdict.evaluate(busy)
        #expect(found.count == 5)
        #expect(found.map(\.topic).contains(.thermal))
        #expect(found.map(\.topic).contains(.cpu))
        #expect(found.map(\.topic).contains(.disk))
    }

    @Test func mostSeriousComesFirst() {
        let found = SystemVerdict.evaluate(calm(cpu: 95, swapGB: 6, thermal: 3))
        #expect(found.first?.kind == .throttling(serious: true))
        #expect(found.first?.severity == .serious)
        // And the order never increases in severity as you go down.
        for (a, b) in zip(found, found.dropFirst()) {
            #expect(a.severity >= b.severity)
        }
    }

    @Test func swappingAndTightMemoryAppearTogether() {
        // Either half alone invites the wrong conclusion.
        let found = kinds(calm(usedGB: 30, totalGB: 32, swapGB: 4, pressure: 4))
        #expect(found.contains(.swapping(gb: 4)))
        #expect(found.contains { if case .memoryTight = $0 { return true }; return false })
    }

    @Test func smallSwapIsNotReported() {
        // macOS keeps a little swap around even when memory is plentiful.
        #expect(SystemVerdict.evaluate(calm(swapGB: 1.2, pressure: 4)).isEmpty)
    }

    @Test func swapSittingOnDiskWithNoPressureIsNotReported() {
        // Reported from the beta: "Out of memory" on a machine using 12.5 of
        // 18 GB. `vm.swapusage` is a standing total, not a rate. macOS never
        // proactively takes swap back, so pages written out during one busy
        // moment sit there indefinitely at no cost. Two thirds of memory free
        // and macOS reporting normal pressure is not a machine out of memory.
        #expect(SystemVerdict.evaluate(
            calm(usedGB: 12.5, totalGB: 18, swapGB: 2.1, pressure: 1, swapPages: 0)).isEmpty)
    }

    @Test func pagingRightNowIsReportedEvenBeforeMacOSRaisesPressure() {
        // The rate is the half that describes what the machine is doing, and it
        // moves before the pressure level does.
        let found = kinds(calm(swapGB: 3, pressure: 1, swapPages: 400))
        #expect(found == [.swapping(gb: 3)])
    }

    @Test func aTrickleOfPagingIsOrdinaryHousekeeping() {
        #expect(SystemVerdict.evaluate(calm(swapGB: 3, pressure: 1, swapPages: 5)).isEmpty)
    }

    @Test func warningLevelPressureAloneSaysNothing() {
        // Measured on a real machine: level 2 sat there steadily with 10 GB of
        // 18 in use and almost no swap. It does not track memory use, so it
        // cannot carry an alarm on its own.
        #expect(SystemVerdict.evaluate(calm(swapGB: 3, pressure: 2, swapPages: 0)).isEmpty)
    }

    @Test func macOSReportingPressureIsTheMoreSeriousOfTheTwo() {
        // Paging alone is worth mentioning; macOS reporting critical is a
        // warning.
        let paging = SystemVerdict.evaluate(calm(swapGB: 3, pressure: 1, swapPages: 400))
        let pressured = SystemVerdict.evaluate(calm(swapGB: 3, pressure: 4))
        #expect(paging.first?.severity == .notable)
        #expect(pressured.first?.severity == .warning)
    }

    @Test func dominantProcessIsNamed() {
        #expect(kinds(calm(cpu: 90, top: ("swift-frontend", 82)))
                == [.busyProcess(name: "swift-frontend", percent: 82)])
    }

    @Test func busyWithoutOneCulpritDoesNotBlameTheTopProcess() {
        // Everything is busy but nothing dominates: naming whatever happens to
        // sort first would be misleading.
        #expect(kinds(calm(cpu: 90, top: ("WindowServer", 12))) == [.busy(percent: 90)])
    }

    @Test func busyWithNoProcessListStillReports() {
        #expect(kinds(calm(cpu: 88, top: nil)) == [.busy(percent: 88)])
    }

    @Test func cpuProducesExactlyOneFinding() {
        // busy and busyProcess are alternatives, never both.
        let found = SystemVerdict.evaluate(calm(cpu: 95, top: ("swift-frontend", 90)))
        #expect(found.filter { $0.topic == .cpu }.count == 1)
    }

    @Test func tightMemoryIsReportedAsAPercentage() {
        let found = SystemVerdict.evaluate(calm(usedGB: 29, totalGB: 32))
        guard case let .memoryTight(percent) = found.first?.kind else {
            Issue.record("expected memoryTight"); return
        }
        #expect((percent - 90.625).magnitude < 0.001)
    }

    @Test func zeroTotalMemoryDoesNotDivideByZero() {
        // Defensive: a sampler that has not produced a reading yet.
        #expect(SystemVerdict.evaluate(calm(usedGB: 0, totalGB: 0)).isEmpty)
    }

    @Test func diskAlmostFullIsReported() {
        #expect(kinds(calm(diskFreeGB: 4)) == [.diskAlmostFull(freeGB: 4)])
    }

    @Test func unknownDiskFreeIsNotTreatedAsFull() {
        // 0 GB free means "not measured yet", not "no space left".
        #expect(SystemVerdict.evaluate(calm(diskFreeGB: 0)).isEmpty)
    }

    @Test func thresholdsAreInclusive() {
        #expect(kinds(calm(cpu: 80)) == [.busy(percent: 80)])
        #expect(kinds(calm(swapGB: 2, pressure: 4)) == [.swapping(gb: 2)])
    }

    @Test func eachFindingCarriesTheTopicThatExplainsIt() {
        #expect(SystemVerdict.evaluate(calm(thermal: 3)).first?.topic == .thermal)
        #expect(SystemVerdict.evaluate(calm(swapGB: 5, pressure: 4)).first?.topic == .memory)
        #expect(SystemVerdict.evaluate(calm(cpu: 95)).first?.topic == .cpu)
        #expect(SystemVerdict.evaluate(calm(diskFreeGB: 2)).first?.topic == .disk)
    }
}
