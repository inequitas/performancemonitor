import Testing
@testable import PerformanceAppCore

@Suite("EnergyPower")
struct EnergyPowerTests {

    // MARK: - mJ → W

    @Test func millijoulesConvertToWatts() {
        // 2000 mJ over 1 s = 2.0 J/s = 2.0 W.
        let w = EnergyPower.watts(energyDelta: 2000, unit: .millijoule, seconds: 1.0)
        #expect(w != nil)
        #expect(abs(w! - 2.0) < 1e-9)
    }

    @Test func millijoulesOverFractionalInterval() {
        // 540 mJ over 1 s ≈ 0.54 W — the spike's measured idle CPU figure.
        let w = EnergyPower.watts(energyDelta: 540, unit: .millijoule, seconds: 1.0)
        #expect(w != nil)
        #expect(abs(w! - 0.54) < 1e-9)
    }

    @Test func millijoulesScaleWithInterval() {
        // 2000 mJ over 2 s = 1.0 W.
        let w = EnergyPower.watts(energyDelta: 2000, unit: .millijoule, seconds: 2.0)
        #expect(w != nil)
        #expect(abs(w! - 1.0) < 1e-9)
    }

    // MARK: - nJ → W (GPU Energy is reported in nanojoules)

    @Test func nanojoulesConvertToWatts() {
        // 20_000_000 nJ = 0.02 J over 1 s = 0.02 W — the spike's idle GPU figure.
        let w = EnergyPower.watts(energyDelta: 20_000_000, unit: .nanojoule, seconds: 1.0)
        #expect(w != nil)
        #expect(abs(w! - 0.02) < 1e-9)
    }

    // MARK: - µJ → W

    @Test func microjoulesConvertToWatts() {
        // 1_000_000 µJ = 1 J over 1 s = 1 W.
        let w = EnergyPower.watts(energyDelta: 1_000_000, unit: .microjoule, seconds: 1.0)
        #expect(w != nil)
        #expect(abs(w! - 1.0) < 1e-9)
    }

    // MARK: - dt guard

    @Test func zeroIntervalReturnsNil() {
        #expect(EnergyPower.watts(energyDelta: 1000, unit: .millijoule, seconds: 0) == nil)
    }

    @Test func negativeIntervalReturnsNil() {
        #expect(EnergyPower.watts(energyDelta: 1000, unit: .millijoule, seconds: -1) == nil)
    }

    // MARK: - counter wrap / negative delta

    @Test func negativeDeltaClampsToZero() {
        // A wrapped or reset counter must never surface as negative power.
        let w = EnergyPower.watts(energyDelta: -5000, unit: .millijoule, seconds: 1.0)
        #expect(w == 0)
    }

    @Test func zeroDeltaIsZeroWatts() {
        let w = EnergyPower.watts(energyDelta: 0, unit: .millijoule, seconds: 1.0)
        #expect(w == 0)
    }

    // MARK: - missing / unknown unit

    @Test func unknownUnitReturnsNil() {
        // A channel with no recognised energy unit yields no reading, not a crash.
        #expect(EnergyPower.watts(energyDelta: 1000, unit: .unknown, seconds: 1.0) == nil)
    }

    // MARK: - C-shim raw-value parity

    @Test func unitRawValuesMatchCShim() {
        // Must stay in sync with CIOReportEnergyUnit in Sources/CIOReport/include/CIOReport.h.
        #expect(EnergyPower.Unit.unknown.rawValue == 0)
        #expect(EnergyPower.Unit.millijoule.rawValue == 1)
        #expect(EnergyPower.Unit.microjoule.rawValue == 2)
        #expect(EnergyPower.Unit.nanojoule.rawValue == 3)
    }
}
