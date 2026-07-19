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
}
