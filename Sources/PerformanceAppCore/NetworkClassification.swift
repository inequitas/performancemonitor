import Foundation

/// Pure classification of `NWPath` properties into a "likely hotspot" verdict.
///
/// macOS itself swaps the Wi-Fi menu bar icon for a chain-link icon when the
/// active path is tethered through a personal hotspot. `NWPath` doesn't
/// expose that directly, but `isExpensive` (set for cellular and
/// cellular-backed personal hotspots) combined with the path actually using
/// Wi-Fi is the same heuristic macOS uses. Extracted as a free function so it
/// can be unit tested without `Network.framework`.
public enum NetworkClassification {
    /// - Parameters:
    ///   - isExpensive: `NWPath.isExpensive` — true for cellular and
    ///     cellular-backed connections such as a personal hotspot.
    ///   - usesWifi: `NWPath.usesInterfaceType(.wifi)`.
    ///   - satisfied: `NWPath.status == .satisfied`.
    public static func isLikelyHotspot(isExpensive: Bool, usesWifi: Bool, satisfied: Bool) -> Bool {
        isExpensive && usesWifi && satisfied
    }
}
