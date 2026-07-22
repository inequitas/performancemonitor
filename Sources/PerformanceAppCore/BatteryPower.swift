import Foundation

/// Pure watt calculation for the battery's instantaneous power draw/input.
/// Source values come from `AppleSmartBattery` (see `BatterySampler`):
/// voltage in volts, amperage in milliamps, signed per Apple's convention
/// (positive = charging / current flowing in, negative = discharging).
public enum BatteryPower {
    public enum Direction: Equatable {
        case charging
        case discharging
        /// Amperage reads exactly zero — battery present but no current flowing
        /// (e.g. fully charged and sitting on AC).
        case idle
    }

    /// Direction derived straight from the amperage sign — independent of any
    /// AC-power-source flag, so it reflects what the battery itself is doing.
    /// Returns `nil` when amperage is unavailable.
    public static func direction(amperageMilliamps: Int?) -> Direction? {
        guard let a = amperageMilliamps else { return nil }
        if a > 0 { return .charging }
        if a < 0 { return .discharging }
        return .idle
    }

    /// Power in watts: `voltage × |amperage| ÷ 1000`. Magnitude only — pair
    /// with `direction(amperageMilliamps:)` for sign/label. Returns `nil` when
    /// either input is missing (e.g. desktops with no battery).
    public static func watts(voltage: Double?, amperageMilliamps: Int?) -> Double? {
        guard let voltage, let amperageMilliamps else { return nil }
        return voltage * abs(Double(amperageMilliamps)) / 1000
    }
}
