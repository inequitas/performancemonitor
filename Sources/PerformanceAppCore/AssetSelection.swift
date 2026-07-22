import Foundation

/// The update channel a running build effectively belongs to. Distinct from
/// any single build's `PMUpdateChannel` Info.plist value: a stable build can
/// still be *effectively* on the beta channel if the user opted in via
/// Settings (see UpdateChecker.effectiveChannel).
public enum UpdateChannel: String, Sendable {
    case stable
    case beta
}

/// Picks, by exact filename, which zip asset a GitHub release's asset list
/// should be downloaded from for a given channel.
///
/// Both stable and beta release builds ship in the same GitHub release (see
/// build_app.sh --beta, which now builds both variants), so a release's
/// asset list can contain either or both of "PerformanceApp.zip" and
/// "PerformanceApp-Beta.zip". Selection is always by exact name — never
/// "the first zip" — so a stable client can never accidentally be handed a
/// beta build, or vice versa.
public enum AssetSelector {
    public static let stableAssetName = "PerformanceApp.zip"
    public static let betaAssetName   = "PerformanceApp-Beta.zip"

    /// Returns the asset name to download for `channel`, or nil if no
    /// suitable asset is present.
    ///
    /// - stable: only ever "PerformanceApp.zip".
    /// - beta: prefers "PerformanceApp-Beta.zip"; if that asset is missing
    ///   from the release (e.g. an older release published before both
    ///   variants were built), falls back to "PerformanceApp.zip" so a beta
    ///   install still rolls forward onto the stable build rather than
    ///   getting stuck with no candidate at all.
    public static func selectAssetName(from assetNames: [String], channel: UpdateChannel) -> String? {
        switch channel {
        case .stable:
            return assetNames.contains(stableAssetName) ? stableAssetName : nil
        case .beta:
            if assetNames.contains(betaAssetName) { return betaAssetName }
            if assetNames.contains(stableAssetName) { return stableAssetName }
            return nil
        }
    }
}
