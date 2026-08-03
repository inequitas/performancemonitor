import Testing
@testable import PerformanceAppCore

@Suite("PSParser")
struct PSParserTests {

    // Representative `ps -arcwwwxo pid,%cpu,%mem,comm` output. First line is the
    // header; %cpu is per-core (so 200.0 = two cores fully pinned). `comm` comes
    // last so that ps does not truncate it to 16 characters.
    private let sample = """
    PID %CPU %MEM COMM
    1234 150.0 3.2 WindowServer
    5678 40.0 1.0 kernel_task
    9012 20.0 5.5 Google Chrome Helper
    3456 0.0 0.8 Finder
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
        let (cpu, _) = PSParser.parse("PID %CPU %MEM COMM", topCount: 10, logicalCPUs: 8)
        #expect(cpu.isEmpty)
    }

    @Test func longNamesSurviveIntact() {
        // The reason comm is the last column: anywhere else ps cuts it at 16
        // characters, which collapses three different WebKit helpers into one
        // name and leaves the process lists showing "Performance Moni".
        let long = """
        PID %CPU %MEM COMM
        1234 10.0 1.0 com.apple.WebKit.WebContent
        """
        let (cpu, _) = PSParser.parse(long, topCount: 10, logicalCPUs: 1)
        #expect(cpu.first?.name == "com.apple.WebKit.WebContent")
    }

    @Test func truncatedAndMalformedLinesAreSkipped() {
        let messy = """
        PID %CPU %MEM COMM
        1234 150.0 3.2 WindowServer
        notapid 10.0 2.0 Foo
        5678 12.0 OnlyThreeCols
        9012 20.0 4.0 Bar
        """
        let (cpu, _) = PSParser.parse(messy, topCount: 10, logicalCPUs: 1)
        // Only the two well-formed rows survive.
        #expect(cpu.count == 2)
        #expect(Set(cpu.map(\.pid)) == [1234, 9012])
    }
}
