import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

// MARK: - Battery

struct BatteryDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Battery", systemImage: batterySystemImage(
                engine.batteryPercent ?? 100,
                charging: engine.batteryIsCharging
            ))
                .font(.title2.weight(.semibold))
                .foregroundStyle(MetricTheme.battery)

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    if let percent = engine.batteryPercent {
                        Text("\(percent)%")
                            .font(.system(size: 28, weight: .bold, design: .rounded))
                            .foregroundStyle(MetricTheme.battery)
                    }
                    detailRow("Source", engine.powerSourceName)
                    detailRow("State", engine.batteryIsCharging ? "Charging" : "Discharging")
                    if let minutes = engine.batteryTimeRemainingMinutes {
                        detailRow(engine.batteryIsCharging ? "Time to full" : "Time remaining",
                                  "\(minutes / 60)h \(minutes % 60)m")
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Health").font(.subheadline.weight(.semibold))
                        Spacer()
                        InfoButton(text: "Capacity %: NominalChargeCapacity ÷ DesignCapacity × 100. This shows how much of the original battery capacity remains.\n\nCycle count: Each full charge/discharge cycle counts as one. Apple considers batteries at peak performance for 1000 cycles (MacBook Pro/Air M-series). After that, capacity may be below 80%.\n\nCondition 'Normal' means the battery is performing within expected parameters. 'Service Recommended' means capacity has dropped significantly and Apple recommends a replacement.")
                    }
                    if let health = engine.batteryHealthPercent {
                        detailRow("Capacity vs. design", String(format: "%.0f%%", health))
                    }
                    detailRow("Condition", engine.batteryCondition)
                    if let cycles = engine.batteryCycleCount {
                        detailRow("Cycle count", engine.batteryDesignCycleCount.map { "\(cycles) / \($0)" } ?? "\(cycles)")
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Electrical").font(.subheadline.weight(.semibold))
                        Spacer()
                        InfoButton(text: "Temperature: Read from AppleSmartBattery IORegistry — no special privileges needed. This is the battery cell temperature, not the CPU temperature.\n\nVoltage: Current battery terminal voltage in volts.\n\nCurrent: Positive = charging (current flowing in). Negative = discharging (current flowing out). Values are in milliamps (mA).\n\nAll values come from the AppleSmartBattery driver which is always accessible without entitlements.")
                    }
                    if let v = engine.batteryVoltage, let a = engine.batteryAmperage {
                        let watts = v * abs(Double(a)) / 1000
                        detailRow(engine.batteryIsCharging ? "Input power" : "Draw",
                                  String(format: "%.1f W", watts))
                    }
                    if let temp = engine.batteryTemperatureC {
                        HStack {
                            Text("Temperature").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f°C", temp))
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(MetricTheme.sensorTempColor(temp, category: "Battery"))
                                .accessibilityValue("\(String(format: "%.1f", temp)) degrees, \(MetricTheme.sensorTempSeverityWord(temp, category: "Battery"))")
                        }
                    }
                    if let voltage = engine.batteryVoltage {
                        detailRow("Voltage", String(format: "%.2f V", voltage))
                    }
                    if let amperage = engine.batteryAmperage {
                        detailRow("Current", "\(amperage) mA")
                    }
                }
            }
            Spacer()
        }
    }
}
