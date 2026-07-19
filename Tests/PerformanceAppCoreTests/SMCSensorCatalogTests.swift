import Testing
@testable import PerformanceAppCore

@Suite("SMCSensorCatalog")
struct SMCSensorCatalogTests {

    @Test func knownCPUKeyReturnsLabelAndCategory() {
        let result = SMCSensorCatalog.categorize(key: "Tp01")
        #expect(result?.label == "CPU Performance Core 1")
        #expect(result?.category == "CPU")
    }

    @Test func knownGPUKeyReturnsGPUCategory() {
        let result = SMCSensorCatalog.categorize(key: "Tg05")
        #expect(result?.category == "GPU")
    }

    @Test func knownBatteryKeyReturnsBatteryCategory() {
        let result = SMCSensorCatalog.categorize(key: "TB0T")
        #expect(result?.label == "Battery")
        #expect(result?.category == "Battery")
    }

    @Test func unknownKeyReturnsNil() {
        #expect(SMCSensorCatalog.categorize(key: "ZZZZ") == nil)
    }

    @Test func emptyKeyReturnsNil() {
        #expect(SMCSensorCatalog.categorize(key: "") == nil)
    }

    @Test func keysAreCaseSensitive() {
        // The catalog is keyed on exact SMC key casing; a lowercase mismatch
        // is treated as unknown rather than being matched loosely.
        #expect(SMCSensorCatalog.categorize(key: "Tp01") != nil)
        #expect(SMCSensorCatalog.categorize(key: "tp01") == nil)
    }
}
