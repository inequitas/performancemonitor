import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

// MARK: - Thermal & Fans

struct ThermalDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Thermal & Fans", systemImage: "thermometer.medium")
                .font(.title2.weight(.semibold))
                .foregroundStyle(engine.thermalState.color)

            // Thermal pressure
            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Thermal Pressure").font(.subheadline.weight(.semibold))
                        Spacer()
                        InfoButton(text: "macOS reports four thermal pressure levels:\n\n• Nominal — system operating normally.\n• Fair — some power reduction to prevent overheating.\n• Serious — significant throttling in effect.\n• Critical — aggressive throttling; performance severely impacted.\n\nThis is read from ProcessInfo.thermalState — the same value macOS uses internally to throttle workloads.")
                    }
                    HStack(spacing: 8) {
                        Circle().fill(engine.thermalState.color).frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(engine.thermalState.label)
                            .font(.system(size: 18, weight: .semibold, design: .rounded))
                            .foregroundStyle(engine.thermalState.color)
                    }
                }
            }

            // Temperatures — each category expandable to individual sensors
            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Temperatures").font(.subheadline.weight(.semibold))
                        Spacer()
                        InfoButton(text: "Read from the System Management Controller (SMC) via IOKit.\n\nCPU and GPU values shown are averages across all cluster sensors. Tap a row to expand individual readings.\n\nBattery temperature is read from the AppleSmartBattery IORegistry entry.")
                    }

                    let groups = Dictionary(grouping: engine.extendedTemperatures, by: \.category)
                    let cpuSensors      = (groups["CPU"]      ?? []).sorted { $0.label < $1.label }
                    let gpuSensors      = (groups["GPU"]      ?? []).sorted { $0.label < $1.label }
                    let trackpadSensors = (groups["Trackpad"] ?? []).sorted { $0.label < $1.label }

                    if let avg = engine.cpuTemperatureC {
                        SensorCategoryRow(
                            icon: "cpu", iconColor: MetricTheme.cpu, label: "CPU", avgCelsius: avg,
                            sensors: cpuSensors.map { ($0.label, $0.celsius) },
                            category: "CPU"
                        )
                    }
                    if let avg = engine.gpuTemperatureC {
                        SensorCategoryRow(
                            icon: "cube.transparent", iconColor: .cyan, label: "GPU", avgCelsius: avg,
                            sensors: gpuSensors.map { ($0.label, $0.celsius) },
                            category: "GPU"
                        )
                    }
                    if let bat = engine.batteryTemperatureC {
                        SensorCategoryRow(
                            icon: "battery.75percent", iconColor: MetricTheme.battery, label: "Battery",
                            avgCelsius: bat, sensors: [],
                            category: "Battery"
                        )
                    }

                    // Storage group
                    let storageSensors = (groups["Storage"] ?? []).sorted { $0.label < $1.label }
                    if !storageSensors.isEmpty {
                        let avg = storageSensors.map(\.celsius).reduce(0, +) / Double(storageSensors.count)
                        SensorCategoryRow(
                            icon: "internaldrive", iconColor: .indigo, label: "Storage", avgCelsius: avg,
                            sensors: storageSensors.map { ($0.label, $0.celsius) },
                            category: "Storage"
                        )
                    }

                    // System group (starts expanded) — Trackpad + board sensors
                    let systemDisplaySensors: [(label: String, celsius: Double)] = {
                        var result: [(label: String, celsius: Double)] = []
                        if !trackpadSensors.isEmpty {
                            if trackpadSensors.count <= 3 {
                                result += trackpadSensors.map { ($0.label, $0.celsius) }
                            } else {
                                let avg = trackpadSensors.map(\.celsius).reduce(0, +) / Double(trackpadSensors.count)
                                result.append(("Trackpad", avg))
                            }
                        }
                        result += (groups["System"] ?? []).sorted { $0.label < $1.label }.map { ($0.label, $0.celsius) }
                        return result
                    }()
                    if !systemDisplaySensors.isEmpty {
                        let avg = systemDisplaySensors.map(\.celsius).reduce(0, +) / Double(systemDisplaySensors.count)
                        SensorCategoryRow(
                            icon: "thermometer", iconColor: .orange, label: "System", avgCelsius: avg,
                            sensors: systemDisplaySensors,
                            category: "System",
                            initiallyExpanded: true
                        )
                    }

                    // Memory group
                    let memorySensors = (groups["Memory"] ?? []).sorted { $0.label < $1.label }
                    if !memorySensors.isEmpty {
                        let avg = memorySensors.map(\.celsius).reduce(0, +) / Double(memorySensors.count)
                        SensorCategoryRow(
                            icon: "memorychip", iconColor: MetricTheme.memory, label: "Memory", avgCelsius: avg,
                            sensors: memorySensors.map { ($0.label, $0.celsius) },
                            category: "Memory"
                        )
                    }

                    if engine.cpuTemperatureC == nil && engine.gpuTemperatureC == nil && engine.extendedTemperatures.isEmpty {
                        Text("No temperature sensors found for this Mac model.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            // Fan speeds (+ airflow temperatures where available)
            if !engine.fans.isEmpty {
                SectionCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Fans").font(.subheadline.weight(.semibold))
                            Spacer()
                            InfoButton(text: "Fan speed is read from the SMC via IOKit.\n\nActual: current measured RPM.\nMin/Max: hardware-defined speed range for this fan.\nAirflow: intake air temperature sensor near each fan.")
                        }
                        let airflow = engine.extendedTemperatures.filter { $0.category == "Airflow" }
                        ForEach(engine.fans) { fan in
                            VStack(alignment: .leading, spacing: 6) {
                                if engine.fans.count > 1 {
                                    Label(fan.label, systemImage: "fan.fill")
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                }
                                detailRow("Speed", "\(fan.actual) RPM")
                                detailRow("Range", "\(fan.min) – \(fan.max) RPM")
                                if fan.max > fan.min {
                                    let progress = Double(fan.actual - fan.min) / Double(fan.max - fan.min)
                                    GeometryReader { geo in
                                        ZStack(alignment: .leading) {
                                            Capsule().fill(Color.secondary.opacity(0.15))
                                                .frame(height: 5)
                                            Capsule().fill(engine.thermalState.color)
                                                .frame(width: geo.size.width * CGFloat(min(max(progress, 0), 1)), height: 5)
                                        }
                                    }
                                    .frame(height: 5)
                                }
                                // Airflow sensor matched to this fan by label (Left/Right)
                                if let a = airflow.first(where: { $0.label.lowercased().contains(fan.label.lowercased()) }) {
                                    detailRow("Airflow", String(format: "%.1f°C", a.celsius))
                                }
                            }
                            if fan.id < engine.fans.count - 1 { Divider() }
                        }
                    }
                }
            }

            Spacer()
        }
    }

}

private struct SensorCategoryRow: View {
    let icon: String
    let iconColor: Color
    let label: String
    let avgCelsius: Double
    let sensors: [(label: String, celsius: Double)]
    let category: String

    @State private var expanded: Bool

    init(icon: String, iconColor: Color, label: String, avgCelsius: Double,
         sensors: [(label: String, celsius: Double)], category: String,
         initiallyExpanded: Bool = false) {
        self.icon = icon
        self.iconColor = iconColor
        self.label = label
        self.avgCelsius = avgCelsius
        self.sensors = sensors
        self.category = category
        _expanded = State(initialValue: initiallyExpanded)
    }

    private func colorFn(_ celsius: Double) -> Color { MetricTheme.sensorTempColor(celsius, category: category) }
    private func severityWord(_ celsius: Double) -> String { MetricTheme.sensorTempSeverityWord(celsius, category: category) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                if sensors.count > 1 {
                    withAnimation(.easeInOut(duration: 0.15)) { expanded.toggle() }
                }
            } label: {
                HStack(spacing: 8) {
                    // Note: contentShape below ensures the Spacer and chevron are tappable
                    ZStack {
                        RoundedRectangle(cornerRadius: 5)
                            .fill(iconColor.opacity(0.15))
                            .frame(width: 22, height: 22)
                        Image(systemName: icon)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(iconColor)
                    }
                    Text(label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(String(format: "%.1f°C", avgCelsius))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(colorFn(avgCelsius))
                        .accessibilityValue("\(String(format: "%.1f", avgCelsius)) degrees, \(severityWord(avgCelsius))")
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(expanded ? 90 : 0))
                        .opacity(sensors.count > 1 ? 1 : 0)
                }
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())

            if expanded {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(sensors, id: \.label) { sensor in
                        HStack {
                            Text(sensor.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(String(format: "%.1f°C", sensor.celsius))
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(colorFn(sensor.celsius))
                                .accessibilityValue("\(String(format: "%.1f", sensor.celsius)) degrees, \(severityWord(sensor.celsius))")
                        }
                        .padding(.leading, 30)
                    }
                }
                .padding(.top, 6)
            }
        }
    }
}
