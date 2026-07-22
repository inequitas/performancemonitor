import Testing
@testable import PerformanceAppCore

@Suite("BatteryPower")
struct BatteryPowerTests {

    // MARK: - direction(amperageMilliamps:)

    @Test func positiveAmperageIsCharging() {
        #expect(BatteryPower.direction(amperageMilliamps: 1500) == .charging)
    }

    @Test func negativeAmperageIsDischarging() {
        #expect(BatteryPower.direction(amperageMilliamps: -800) == .discharging)
    }

    @Test func zeroAmperageIsIdle() {
        #expect(BatteryPower.direction(amperageMilliamps: 0) == .idle)
    }

    @Test func nilAmperageHasNoDirection() {
        #expect(BatteryPower.direction(amperageMilliamps: nil) == nil)
    }

    // MARK: - watts(voltage:amperageMilliamps:)

    @Test func wattsUsesMagnitudeOfDischargingCurrent() {
        // 12.0 V at -1000 mA discharge → 12.0 W draw (sign dropped, direction conveyed separately).
        let watts = BatteryPower.watts(voltage: 12.0, amperageMilliamps: -1000)
        #expect(watts == 12.0)
    }

    @Test func wattsUsesMagnitudeOfChargingCurrent() {
        let watts = BatteryPower.watts(voltage: 12.0, amperageMilliamps: 1000)
        #expect(watts == 12.0)
    }

    @Test func wattsIsZeroWhenAmperageIsZero() {
        let watts = BatteryPower.watts(voltage: 12.0, amperageMilliamps: 0)
        #expect(watts == 0)
    }

    @Test func wattsIsNilWhenVoltageMissing() {
        #expect(BatteryPower.watts(voltage: nil, amperageMilliamps: 1000) == nil)
    }

    @Test func wattsIsNilWhenAmperageMissing() {
        #expect(BatteryPower.watts(voltage: 12.0, amperageMilliamps: nil) == nil)
    }

    @Test func wattsIsNilWhenBothMissing() {
        // Desktops with no battery report neither value.
        #expect(BatteryPower.watts(voltage: nil, amperageMilliamps: nil) == nil)
    }

    @Test func wattsMatchesExpectedFractionalValue() {
        // 12.6 V at 2350 mA ≈ 29.61 W — realistic MacBook charge scenario.
        let watts = BatteryPower.watts(voltage: 12.6, amperageMilliamps: 2350)
        #expect(watts != nil)
        #expect(abs(watts! - 29.61) < 0.001)
    }
}
