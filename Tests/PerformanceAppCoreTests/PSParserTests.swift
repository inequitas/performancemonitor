import Testing
@testable import PerformanceAppCore

@Suite("PSParser")
struct PSParserTests {

    // Representative `ps -arcwwwxo pid,comm,%cpu,%mem` output. First line is the
    // header; %cpu is per-core (so 200.0 = two cores fully pinned).
    private let sample = """
    PID COMM %CPU %MEM
    1234 WindowServer 150.0 3.2
    5678 kernel_task 40.0 1.0
    9012 Google Chrome Helper 20.0 5.5
    3456 Finder 0.0 0.8
    """

    @Test func headerIsDropped() {
        let (cpu, mem) = PSParser.parse(sample, topCount: 10, logicalCPUs: 10)
        #expect(cpu.count == 4)
        #expect(mem.count == 4)
        #expect(!cpu.contains { $0.name == "COMM" })
    }

    @Test func cpuIsRescaledByLogicalCores() {
        // 150.0 per-core / 10 logical cores = 15.0% of total capacity.
        let (cpu, _) = PSParser.parse(sample, topCount: 10, logicalCPUs: 10)
        let top = cpu.first!
        #expect(top.name == "WindowServer")
        #expect(top.pid == 1234)
        #expect(top.value == 15.0)
    }

    @Test func multiWordCommandNamesArePreserved() {
        let (cpu, _) = PSParser.parse(sample, topCount: 10, logicalCPUs: 1)
        #expect(cpu.contains { $0.name == "Google Chrome Helper" && $0.pid == 9012 })
    }

    @Test func sortedDescendingAndTruncatedToTopCount() {
        let (cpu, mem) = PSParser.parse(sample, topCount: 2, logicalCPUs: 1)
        #expect(cpu.count == 2)
        #expect(cpu[0].value >= cpu[1].value)
        #expect(cpu[0].name == "WindowServer")
        // Memory sort is independent of CPU sort.
        #expect(mem.count == 2)
        #expect(mem[0].name == "Google Chrome Helper")   // 5.5 %MEM is highest
    }

    @Test func logicalCPUsClampedToAtLeastOne() {
        // 0 (or negative) logical cores must not divide-by-zero; clamps to 1.
        let (cpu, _) = PSParser.parse(sample, topCount: 10, logicalCPUs: 0)
        #expect(cpu.first!.value == 150.0)
    }

    @Test func emptyOutputYieldsNothing() {
        let (cpu, mem) = PSParser.parse("", topCount: 10, logicalCPUs: 8)
        #expect(cpu.isEmpty)
        #expect(mem.isEmpty)
    }

    @Test func headerOnlyYieldsNothing() {
        let (cpu, _) = PSParser.parse("PID COMM %CPU %MEM", topCount: 10, logicalCPUs: 8)
        #expect(cpu.isEmpty)
    }

    @Test func truncatedAndMalformedLinesAreSkipped() {
        let messy = """
        PID COMM %CPU %MEM
        1234 WindowServer 150.0 3.2
        notapid Foo 10.0 2.0
        5678 OnlyThreeCols 12.0
        9012 Bar 20.0 4.0
        """
        let (cpu, _) = PSParser.parse(messy, topCount: 10, logicalCPUs: 1)
        // Only the two well-formed rows survive.
        #expect(cpu.count == 2)
        #expect(Set(cpu.map(\.pid)) == [1234, 9012])
    }
}
