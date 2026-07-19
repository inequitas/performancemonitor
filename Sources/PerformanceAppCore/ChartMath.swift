import Foundation

/// Pure helpers for computing chart axis bounds from history arrays.
public enum ChartMath {
    /// 95th-percentile max — prevents rare big spikes from collapsing all smaller bars.
    public static func p95Max(_ a: [Double], _ b: [Double]) -> Double {
        let all = (a + b).filter { $0 > 0 }.sorted()
        guard !all.isEmpty else { return 1 }
        return max(all[Int(Double(all.count) * 0.95)], 1)
    }

    public static func absoluteMax(_ a: [Double], _ b: [Double]) -> Double {
        max(a.max() ?? 0, b.max() ?? 0, 1)
    }
}
