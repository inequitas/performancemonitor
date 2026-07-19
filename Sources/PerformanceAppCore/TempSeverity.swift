import Foundation

/// Severity bucket for a sensor temperature reading, independent of any
/// color representation — `MetricTheme.sensorTempColor` maps this to a
/// SwiftUI `Color`.
public enum TempSeverity: Equatable {
    case normal, warning, elevated, critical
}

/// Pure temperature → severity mapping. Thresholds vary by sensor category
/// (CPU/GPU run hotter than battery) — extracted verbatim from
/// `MetricTheme.sensorTempColor`.
public enum TempSeverityMapper {
    public static func severity(celsius: Double, category: String) -> TempSeverity {
        switch category {
        case "CPU", "GPU":
            return celsius < 60 ? .normal : celsius < 75 ? .warning : celsius < 90 ? .elevated : .critical
        case "Battery":
            return celsius < 35 ? .normal : celsius < 45 ? .warning : celsius < 55 ? .elevated : .critical
        default:
            return celsius < 40 ? .normal : celsius < 55 ? .warning : celsius < 70 ? .elevated : .critical
        }
    }
}
