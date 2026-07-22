import Testing
@testable import PerformanceAppCore

@Suite("NetworkClassification")
struct NetworkClassificationTests {

    @Test func expensiveWifiSatisfiedIsHotspot() {
        #expect(NetworkClassification.isLikelyHotspot(isExpensive: true, usesWifi: true, satisfied: true) == true)
    }

    @Test func expensiveWithoutWifiIsNotHotspot() {
        #expect(NetworkClassification.isLikelyHotspot(isExpensive: true, usesWifi: false, satisfied: true) == false)
    }

    @Test func nonExpensiveWifiIsNotHotspot() {
        #expect(NetworkClassification.isLikelyHotspot(isExpensive: false, usesWifi: true, satisfied: true) == false)
    }

    @Test func unsatisfiedPathIsNotHotspot() {
        #expect(NetworkClassification.isLikelyHotspot(isExpensive: true, usesWifi: true, satisfied: false) == false)
    }

    @Test func nothingSetIsNotHotspot() {
        #expect(NetworkClassification.isLikelyHotspot(isExpensive: false, usesWifi: false, satisfied: false) == false)
    }
}
