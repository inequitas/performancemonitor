import Foundation

/// Severity bucket for a live metric value compared against its configured
/// alert threshold, independent of any color representation — the menu-bar
/// renderer maps this to the default / orange / red drawing color.
public enum ThresholdSeverity: Equatable {
    case normal, warning, critical
}

/// Pure value+threshold → severity mapping, shared by every menu-bar metric
/// that has an applicable alert threshold (CPU %, GPU %, memory %, disk free
/// space).
///
/// Two comparison directions exist because "bad" points opposite ways for
/// different metrics: CPU/GPU/memory usage is bad when it climbs *above* the
/// threshold, while disk free space is bad when it falls *below* it.
public enum ThresholdSeverityMapper {

    public enum Direction: Equatable {
        /// Usage-style metric: crossing at/above the threshold is bad (CPU, GPU, memory %).
        case highIsBad
        /// Headroom-style metric: crossing at/below the threshold is bad (disk free space).
        case lowIsBad
    }

    /// How far past the threshold a value must travel before severity
    /// escalates from `.warning` (orange) to `.critical` (red). Fixed at 10:
    /// for the percentage-based metrics (CPU/GPU/memory, 0-100 range) that
    /// reads as 10 percentage points — a pragmatic "well past the line"
    /// margin. For disk free space (GB, `.lowIsBad`) the same constant is
    /// reused as 10 GB beyond the threshold, which stays comparably
    /// conservative given the typical 5-20 GB threshold range users set.
    public static let criticalMargin: Double = 10

    /// - Parameters:
    ///   - value: the metric's current live value.
    ///   - threshold: the user-configured alert threshold, or `nil` when no
    ///     threshold is configured/applicable for this metric right now —
    ///     always yields `.normal` in that case.
    public static func severity(value: Double, threshold: Double?, direction: Direction) -> ThresholdSeverity {
        guard let threshold else { return .normal }
        switch direction {
        case .highIsBad:
            if value >= threshold + criticalMargin { return .critical }
            if value >= threshold { return .warning }
            return .normal
        case .lowIsBad:
            if value <= threshold - criticalMargin { return .critical }
            if value <= threshold { return .warning }
            return .normal
        }
    }
}
