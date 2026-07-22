import Testing
@testable import PerformanceAppCore

@Suite("NetworkFormatting")
struct NetworkFormattingTests {

    @Test func kilobitsFormatting() {
        #expect(NetworkFormatting.formatSpeed(kbps: 0) == "0k")
        #expect(NetworkFormatting.formatSpeed(kbps: 512) == "512k")
        #expect(NetworkFormatting.formatSpeed(kbps: 999) == "999k")
    }

    @Test func megabitsFormatting() {
        #expect(NetworkFormatting.formatSpeed(kbps: 1000) == "1.0m")
        #expect(NetworkFormatting.formatSpeed(kbps: 9_400) == "9.4m")
        #expect(NetworkFormatting.formatSpeed(kbps: 12_000) == "12m")
        #expect(NetworkFormatting.formatSpeed(kbps: 999_000) == "999m")
    }

    @Test func gigabitsFormatting() {
        #expect(NetworkFormatting.formatSpeed(kbps: 1_000_000) == "1.0g")
        #expect(NetworkFormatting.formatSpeed(kbps: 9_500_000) == "9.5g")
        #expect(NetworkFormatting.formatSpeed(kbps: 12_000_000) == "12g")
    }

    @Test func dataUsageBytesFormatting() {
        #expect(NetworkFormatting.formatDataUsage(bytes: 0) == "0 B")
        #expect(NetworkFormatting.formatDataUsage(bytes: 512) == "512 B")
    }

    @Test func dataUsageKilobytesFormatting() {
        #expect(NetworkFormatting.formatDataUsage(bytes: 1_500) == "1.5 KB")
        #expect(NetworkFormatting.formatDataUsage(bytes: 999_000) == "999.0 KB")
    }

    @Test func dataUsageMegabytesAndGigabytesFormatting() {
        #expect(NetworkFormatting.formatDataUsage(bytes: 1_500_000) == "1.5 MB")
        #expect(NetworkFormatting.formatDataUsage(bytes: 2_300_000_000) == "2.3 GB")
    }
}
