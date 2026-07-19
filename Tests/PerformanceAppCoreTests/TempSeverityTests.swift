import Testing
@testable import PerformanceAppCore

@Suite("TempSeverityMapper")
struct TempSeverityTests {

    @Test func cpuAndGPUThresholds() {
        #expect(TempSeverityMapper.severity(celsius: 59, category: "CPU") == .normal)
        #expect(TempSeverityMapper.severity(celsius: 60, category: "CPU") == .warning)
        #expect(TempSeverityMapper.severity(celsius: 74, category: "GPU") == .warning)
        #expect(TempSeverityMapper.severity(celsius: 75, category: "GPU") == .elevated)
        #expect(TempSeverityMapper.severity(celsius: 89, category: "CPU") == .elevated)
        #expect(TempSeverityMapper.severity(celsius: 90, category: "CPU") == .critical)
    }

    @Test func batteryThresholdsAreStricter() {
        #expect(TempSeverityMapper.severity(celsius: 34, category: "Battery") == .normal)
        #expect(TempSeverityMapper.severity(celsius: 35, category: "Battery") == .warning)
        #expect(TempSeverityMapper.severity(celsius: 44, category: "Battery") == .warning)
        #expect(TempSeverityMapper.severity(celsius: 45, category: "Battery") == .elevated)
        #expect(TempSeverityMapper.severity(celsius: 54, category: "Battery") == .elevated)
        #expect(TempSeverityMapper.severity(celsius: 55, category: "Battery") == .critical)
    }

    @Test func unknownCategoryFallsBackToDefaultThresholds() {
        #expect(TempSeverityMapper.severity(celsius: 39, category: "Storage") == .normal)
        #expect(TempSeverityMapper.severity(celsius: 40, category: "Storage") == .warning)
        #expect(TempSeverityMapper.severity(celsius: 54, category: "Storage") == .warning)
        #expect(TempSeverityMapper.severity(celsius: 55, category: "Storage") == .elevated)
        #expect(TempSeverityMapper.severity(celsius: 69, category: "Storage") == .elevated)
        #expect(TempSeverityMapper.severity(celsius: 70, category: "Storage") == .critical)
    }

    @Test func emptyCategoryUsesDefaultThresholds() {
        #expect(TempSeverityMapper.severity(celsius: 0, category: "") == .normal)
    }
}
