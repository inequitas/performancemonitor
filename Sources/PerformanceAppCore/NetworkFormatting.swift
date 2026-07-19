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
}
