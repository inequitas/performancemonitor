import Testing
@testable import PerformanceAppCore

@Suite("ChartMath")
struct ChartMathTests {

    @Test func absoluteMaxPicksLargestAcrossBothArrays() {
        #expect(ChartMath.absoluteMax([1, 5, 3], [2, 4]) == 5)
        #expect(ChartMath.absoluteMax([2, 4], [1, 5, 3]) == 5)
    }

    @Test func absoluteMaxFloorsAtOneForAllZero() {
        #expect(ChartMath.absoluteMax([0, 0], [0]) == 1)
    }

    @Test func absoluteMaxEmptyArraysReturnsFloor() {
        #expect(ChartMath.absoluteMax([], []) == 1)
    }

    @Test func p95MaxEmptyArraysReturnsOne() {
        #expect(ChartMath.p95Max([], []) == 1)
    }

    @Test func p95MaxIgnoresNonPositiveValues() {
        // Only positive values participate; an array of zeros/negatives is
        // treated as empty and floors to 1.
        #expect(ChartMath.p95Max([0, 0, -1], [0]) == 1)
    }

    @Test func p95MaxUsesPercentileNotAbsoluteMax() {
        // 100 values 1...100 in `a`; the 95th-percentile index should sit
        // near 96, well below the true max of 100.
        let a = (1...100).map(Double.init)
        let result = ChartMath.p95Max(a, [])
        #expect(result == 96)
    }

    @Test func p95MaxFloorsAtOne() {
        #expect(ChartMath.p95Max([0.1, 0.2], [0.1]) == 1)
    }
}
