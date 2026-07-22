import Testing
@testable import PerformanceAppCore

@Suite("ThresholdSeverityMapper")
struct ThresholdSeverityTests {

    @Test func highIsBadBelowThresholdIsNormal() {
        #expect(ThresholdSeverityMapper.severity(value: 89, threshold: 90, direction: .highIsBad) == .normal)
    }

    @Test func highIsBadAtThresholdIsWarning() {
        #expect(ThresholdSeverityMapper.severity(value: 90, threshold: 90, direction: .highIsBad) == .warning)
    }

    @Test func highIsBadJustBelowCriticalMarginIsWarning() {
        #expect(ThresholdSeverityMapper.severity(value: 99, threshold: 90, direction: .highIsBad) == .warning)
    }

    @Test func highIsBadAtCriticalMarginIsCritical() {
        #expect(ThresholdSeverityMapper.severity(value: 100, threshold: 90, direction: .highIsBad) == .critical)
    }

    @Test func lowIsBadAboveThresholdIsNormal() {
        #expect(ThresholdSeverityMapper.severity(value: 11, threshold: 10, direction: .lowIsBad) == .normal)
    }

    @Test func lowIsBadAtThresholdIsWarning() {
        #expect(ThresholdSeverityMapper.severity(value: 10, threshold: 10, direction: .lowIsBad) == .warning)
    }

    @Test func lowIsBadJustAboveCriticalMarginIsWarning() {
        #expect(ThresholdSeverityMapper.severity(value: 1, threshold: 10, direction: .lowIsBad) == .warning)
    }

    @Test func lowIsBadAtCriticalMarginIsCritical() {
        #expect(ThresholdSeverityMapper.severity(value: 0, threshold: 10, direction: .lowIsBad) == .critical)
    }

    @Test func noThresholdConfiguredIsAlwaysNormal() {
        #expect(ThresholdSeverityMapper.severity(value: 999, threshold: nil, direction: .highIsBad) == .normal)
        #expect(ThresholdSeverityMapper.severity(value: -999, threshold: nil, direction: .lowIsBad) == .normal)
    }

    @Test func negativeValuesAreHandled() {
        #expect(ThresholdSeverityMapper.severity(value: -5, threshold: 0, direction: .highIsBad) == .normal)
        #expect(ThresholdSeverityMapper.severity(value: -10, threshold: 0, direction: .lowIsBad) == .critical)
    }

    @Test func zeroThresholdEdgeCases() {
        #expect(ThresholdSeverityMapper.severity(value: 0, threshold: 0, direction: .highIsBad) == .warning)
        #expect(ThresholdSeverityMapper.severity(value: 0, threshold: 0, direction: .lowIsBad) == .warning)
    }
}
