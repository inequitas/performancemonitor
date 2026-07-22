import Testing
@testable import PerformanceAppCore

@Suite("AssetSelector")
struct AssetSelectionTests {

    @Test func stableChannelPicksOnlyTheStableAsset() {
        let names = ["PerformanceApp.zip", "PerformanceApp.zip.sig"]
        #expect(AssetSelector.selectAssetName(from: names, channel: .stable) == "PerformanceApp.zip")
    }

    @Test func stableChannelIgnoresBetaAssetEvenIfPresent() {
        let names = ["PerformanceApp.zip", "PerformanceApp-Beta.zip"]
        #expect(AssetSelector.selectAssetName(from: names, channel: .stable) == "PerformanceApp.zip")
    }

    @Test func stableChannelReturnsNilWhenStableAssetMissing() {
        let names = ["PerformanceApp-Beta.zip"]
        #expect(AssetSelector.selectAssetName(from: names, channel: .stable) == nil)
    }

    @Test func betaChannelPrefersTheBetaAsset() {
        let names = ["PerformanceApp.zip", "PerformanceApp-Beta.zip"]
        #expect(AssetSelector.selectAssetName(from: names, channel: .beta) == "PerformanceApp-Beta.zip")
    }

    @Test func betaChannelFallsBackToStableAssetWhenBetaAssetMissing() {
        let names = ["PerformanceApp.zip"]
        #expect(AssetSelector.selectAssetName(from: names, channel: .beta) == "PerformanceApp.zip")
    }

    @Test func betaChannelReturnsNilWhenNeitherAssetPresent() {
        let names = ["SomeOtherApp.zip"]
        #expect(AssetSelector.selectAssetName(from: names, channel: .beta) == nil)
    }

    @Test func selectionNeverPicksAnUnrelatedFirstZip() {
        // Regression guard for the old "first .zip asset" behaviour: an
        // unrelated zip listed before the real asset must never be chosen.
        let names = ["SomeOtherApp.zip", "PerformanceApp.zip"]
        #expect(AssetSelector.selectAssetName(from: names, channel: .stable) == "PerformanceApp.zip")
        #expect(AssetSelector.selectAssetName(from: names, channel: .beta) == "PerformanceApp.zip")
    }
}
