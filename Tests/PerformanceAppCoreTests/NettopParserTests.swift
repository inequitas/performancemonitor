import Testing
@testable import PerformanceAppCore

@Suite("NettopParser")
struct NettopParserTests {

    // `nettop -P -x -L 1 -J bytes_in,bytes_out` — CSV with a header row.
    private let sample = """
    ,bytes_in,bytes_out,
    com.apple.WebKit.Networking.12345,1000,2000,
    Safari.6789,500,0,
    mDNSResponder.55,10,20,
    """

    @Test func headerIsDroppedAndCountersParsed() {
        let counters = NettopParser.parse(sample)
        #expect(counters.count == 3)
        #expect(counters["com.apple.WebKit.Networking.12345"] == NetBytes(bytesIn: 1000, bytesOut: 2000))
    }

    @Test func malformedRowsSkipped() {
        let messy = """
        ,bytes_in,bytes_out,
        Good.1,100,200,
        Truncated.2,onlyone
        NaN.3,abc,def,
        """
        let counters = NettopParser.parse(messy)
        #expect(counters.count == 1)
        #expect(counters["Good.1"] == NetBytes(bytesIn: 100, bytesOut: 200))
    }

    @Test func ratesComputeThroughputAndDropTrailingComponent() {
        let previous: [String: NetBytes] = ["Safari.6789": NetBytes(bytesIn: 0, bytesOut: 0)]
        let current: [String: NetBytes] = ["Safari.6789": NetBytes(bytesIn: 1024, bytesOut: 1024)]
        let rows = NettopParser.rates(current: current, previous: previous, elapsed: 1, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].name == "Safari")           // ".6789" dropped
        #expect(rows[0].value == 2.0)               // (1024+1024)/1/1024 = 2 kB/s
    }

    @Test func belowThresholdProcessesAreDropped() {
        // 10 bytes over 1s = ~0.0098 kB/s, under the 0.05 kB/s floor.
        let current: [String: NetBytes] = ["Quiet.1": NetBytes(bytesIn: 10, bytesOut: 0)]
        let rows = NettopParser.rates(current: current, previous: [:], elapsed: 1, topCount: 10)
        #expect(rows.isEmpty)
    }

    @Test func missingPreviousTreatedAsZero() {
        let current: [String: NetBytes] = ["New.1": NetBytes(bytesIn: 4096, bytesOut: 4096)]
        let rows = NettopParser.rates(current: current, previous: [:], elapsed: 1, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].value == 8.0)
    }

    @Test func counterResetDoesNotProduceNegativeRate() {
        // Current below previous (counter reset) clamps the delta to zero.
        let previous: [String: NetBytes] = ["App.1": NetBytes(bytesIn: 10_000, bytesOut: 10_000)]
        let current: [String: NetBytes] = ["App.1": NetBytes(bytesIn: 5, bytesOut: 5)]
        let rows = NettopParser.rates(current: current, previous: previous, elapsed: 1, topCount: 10)
        #expect(rows.isEmpty)
    }

    @Test func sortedDescendingAndTruncated() {
        let current: [String: NetBytes] = [
            "Big.1": NetBytes(bytesIn: 100_000, bytesOut: 0),
            "Mid.2": NetBytes(bytesIn: 50_000, bytesOut: 0),
            "Small.3": NetBytes(bytesIn: 5_000, bytesOut: 0),
        ]
        let rows = NettopParser.rates(current: current, previous: [:], elapsed: 1, topCount: 2)
        #expect(rows.count == 2)
        #expect(rows[0].name == "Big")
        #expect(rows[1].name == "Mid")
    }

    @Test func nameWithoutDotIsKeptWhole() {
        let current: [String: NetBytes] = ["kernel": NetBytes(bytesIn: 100_000, bytesOut: 0)]
        let rows = NettopParser.rates(current: current, previous: [:], elapsed: 1, topCount: 10)
        #expect(rows[0].name == "kernel")
    }

    @Test func zeroElapsedYieldsNothing() {
        let current: [String: NetBytes] = ["App.1": NetBytes(bytesIn: 100_000, bytesOut: 0)]
        #expect(NettopParser.rates(current: current, previous: [:], elapsed: 0, topCount: 10).isEmpty)
    }

    // Process-list sampling now runs on its own throttled (~3s) cadence rather
    // than every 1s engine tick, so the elapsed gap between two nettop samples
    // varies. `rates` must divide by the *actual* elapsed time, not assume 1s.
    @Test func variableElapsedIntervalComputesCorrectRate() {
        let previous: [String: NetBytes] = ["Safari.6789": NetBytes(bytesIn: 0, bytesOut: 0)]
        let current: [String: NetBytes] = ["Safari.6789": NetBytes(bytesIn: 3072, bytesOut: 3072)]
        // 6144 bytes over 3s = 2 kB/s — half of what a naive "assume 1s" calc
        // would report for the same byte delta.
        let rows = NettopParser.rates(current: current, previous: previous, elapsed: 3, topCount: 10)
        #expect(rows.count == 1)
        #expect(rows[0].value == 2.0)
    }
}
