import Foundation

/// Pure parser for the `SMART Status` line of `diskutil info /dev/disk0`.
///
/// Extracted from `MetricsEngine.fetchSmartStatus` in the Part-B decomposition.
public enum SMARTParser {
    /// Returns the SMART status value ("Verified", "Not Supported", …) from
    /// `diskutil info` output, or `nil` when no `SMART Status` line is present.
    public static func parse(_ diskutilOutput: String) -> String? {
        diskutilOutput.components(separatedBy: "\n")
            .first { $0.contains("SMART Status") }?
            .components(separatedBy: ":")
            .last?
            .trimmingCharacters(in: .whitespaces)
    }
}
