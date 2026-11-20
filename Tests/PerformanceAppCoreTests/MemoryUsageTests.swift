import Testing
@testable import PerformanceAppCore

@Suite("MemoryUsage")
struct MemoryUsageTests {
    @Test func excludesReclaimablePagesAndIncludesPhysicalCompressor() {
        let usage = MemoryUsage(internalPages: 851_968, purgeablePages: 65_536,
                                wiredPages: 131_072, compressedPages: 32_768, pageSize: 16_384)
        #expect(usage.appGB == 12)
        #expect(usage.wiredGB == 2)
        #expect(usage.compressedGB == 0.5)
        #expect(usage.usedGB == 14.5)
    }

    @Test func supportsFourKilobytePages() {
        let usage = MemoryUsage(internalPages: 262_144, purgeablePages: 0,
                                wiredPages: 262_144, compressedPages: 262_144, pageSize: 4_096)
        #expect(usage.usedGB == 3)
    }

    @Test func inconsistentPurgeableCounterCannotUnderflow() {
        let usage = MemoryUsage(internalPages: 1, purgeablePages: 2,
                                wiredPages: 0, compressedPages: 0, pageSize: 16_384)
        #expect(usage.appGB == 0)
        #expect(usage.usedGB == 0)
    }
}
