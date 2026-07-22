import Testing
@testable import PerformanceAppCore

@Suite("SMCPowerCatalog")
struct SMCPowerCatalogTests {

    @Test func systemPowerKeyReturnsLabel() {
        #expect(SMCPowerCatalog.categorize(key: "PSTR") == "System Power")
    }

    @Test func systemPowerKeyConstantMatchesCatalogEntry() {
        #expect(SMCPowerCatalog.categorize(key: SMCPowerCatalog.systemPowerKey) != nil)
    }

    @Test func unknownPowerKeyReturnsNil() {
        // e.g. PDTR/PZC0 — seen in the spike but not catalogued (unconfirmed meaning).
        #expect(SMCPowerCatalog.categorize(key: "PDTR") == nil)
    }

    @Test func emptyKeyReturnsNil() {
        #expect(SMCPowerCatalog.categorize(key: "") == nil)
    }
}
