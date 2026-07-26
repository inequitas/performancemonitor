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

    /// The menu bar reserves a fixed column width per metric, sized from the
    /// single widest string each formatter can ever produce (see
    /// `ExtraMenuBarController.maxTextLabel`/`maxSparkLabel`, both built from
    /// a 4-character speed token such as "9.9m"). If `formatSpeed` ever grew a
    /// 5th character the reserved column would be too narrow and the menu bar
    /// item would start reflowing again — the exact regression the fixed-width
    /// rendering is meant to prevent. This sweeps representative values across
    /// every unit (k/m/g), including the boundary just below/above each
    /// rollover, and locks in the 4-character ceiling.
    @Test func formatSpeedNeverExceedsFourCharacters() {
        let boundaryAndSampleValues: [Double] = [
            0, 1, 512, 999,                                   // k
            1_000, 9_400, 9_999, 10_000, 12_000, 999_000,     // m
            1_000_000, 9_499_999, 9_999_999, 10_000_000,       // g
            12_000_000, 999_000_000
        ]
        for kbps in boundaryAndSampleValues {
            let s = NetworkFormatting.formatSpeed(kbps: kbps)
            #expect(s.count <= 4, "formatSpeed(\(kbps)) = \"\(s)\" exceeds the 4-character column budget")
        }
    }
}
