import Foundation

/// Pure conversion from an IOReport "Energy Model" energy delta to average power
/// in watts. IOReport exposes each domain as a cumulative energy counter in a
/// per-channel native unit (mJ on CPU/DRAM, nJ on the GPU, occasionally µJ);
/// the sampler differences successive reads and this turns (Δenergy, unit, Δt)
/// into watts. Kept free of any IOReport/CoreFoundation types so it is unit
/// testable in isolation.
public enum EnergyPower {

    /// Native energy unit of a raw counter. Mirrors `CIOReportEnergyUnit` in the
    /// C shim (raw values kept in sync so a decoded C sample maps straight over).
    public enum Unit: Int32 {
        case unknown    = 0
        case millijoule = 1
        case microjoule = 2
        case nanojoule  = 3

        /// Joules per one unit — the factor that turns a raw energy count into J.
        var joulesPerUnit: Double? {
            switch self {
            case .millijoule: return 1e-3
            case .microjoule: return 1e-6
            case .nanojoule:  return 1e-9
            case .unknown:    return nil
            }
        }
    }

    /// Average power over the interval: `energyJoules / seconds`.
    ///
    /// - `energyDelta` is the difference of two cumulative counters in `unit`.
    /// - Returns `nil` when the unit is unknown or `seconds <= 0` (guards a
    ///   zero/negative `Δt` that would divide by zero or invert the sign).
    /// - A negative `energyDelta` (counter wrap or a re-subscribe resetting the
    ///   baseline) is clamped to `0` rather than reported as negative power.
    public static func watts(energyDelta: Int64, unit: Unit, seconds: Double) -> Double? {
        guard let joulesPerUnit = unit.joulesPerUnit else { return nil }
        guard seconds > 0 else { return nil }
        guard energyDelta > 0 else { return 0 }
        let joules = Double(energyDelta) * joulesPerUnit
        return joules / seconds
    }
}
