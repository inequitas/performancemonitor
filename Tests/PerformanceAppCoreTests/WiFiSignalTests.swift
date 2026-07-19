import Testing
@testable import PerformanceAppCore

@Suite("WiFiSignal")
struct WiFiSignalTests {

    @Test func barsThresholds() {
        #expect(WiFiSignal.bars(forRSSI: -40) == 4)
        #expect(WiFiSignal.bars(forRSSI: -50) == 4)   // boundary: >= -50 is 4 bars
        #expect(WiFiSignal.bars(forRSSI: -51) == 3)
        #expect(WiFiSignal.bars(forRSSI: -65) == 3)   // boundary: >= -65 is 3 bars
        #expect(WiFiSignal.bars(forRSSI: -66) == 2)
        #expect(WiFiSignal.bars(forRSSI: -75) == 2)   // boundary: >= -75 is 2 bars
        #expect(WiFiSignal.bars(forRSSI: -76) == 1)
        #expect(WiFiSignal.bars(forRSSI: -100) == 1)
    }

    @Test func labelMatchesBarCount() {
        #expect(WiFiSignal.label(forBars: 4) == "Excellent")
        #expect(WiFiSignal.label(forBars: 3) == "Good")
        #expect(WiFiSignal.label(forBars: 2) == "Fair")
        #expect(WiFiSignal.label(forBars: 1) == "Weak")
    }

    @Test func labelFallsBackToWeakForOutOfRangeBarCounts() {
        #expect(WiFiSignal.label(forBars: 0) == "Weak")
        #expect(WiFiSignal.label(forBars: 5) == "Weak")
    }
}
