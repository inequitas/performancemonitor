import Foundation

/// Pure formatters for network throughput display.
public enum NetworkFormatting {
    /// Formats a kbps value as a compact string ("512k", "12.3m", "1.0g").
    public static func formatSpeed(kbps: Double) -> String {
        if kbps < 1000 { return String(format: "%.0fk", kbps) }
        let mbps = kbps / 1000
        if mbps < 1000 { return mbps < 10 ? String(format: "%.1fm", mbps) : String(format: "%.0fm", mbps) }
        let gbps = mbps / 1000
        return gbps < 10 ? String(format: "%.1fg", gbps) : String(format: "%.0fg", gbps)
    }

    /// Formats a cumulative byte count as a compact data-usage string
    /// ("512 B", "3.4 KB", "1.2 GB"), using decimal (1000-based) units to
    /// match how carriers/macOS typically report data usage.
    public static func formatDataUsage(bytes: UInt64) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1000 && unitIndex < units.count - 1 {
            value /= 1000
            unitIndex += 1
        }
        if unitIndex == 0 { return "\(Int(value)) \(units[unitIndex])" }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
