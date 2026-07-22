import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

// MARK: - CPU

struct CPUDetailView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var style: ChartDisplayStyle = .area

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(String(localized: "CPU"), systemImage: MetricsEngine.Panel.cpu.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MetricTheme.cpu)
                Spacer()
                ChartStylePicker(style: $style)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: "%.1f%%", engine.cpuUsagePercent))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundStyle(MetricTheme.cpu)
                    MetricChart(values: engine.cpuHistory, unit: "%", fixedMax: 100, color: MetricTheme.cpu, style: style, accessibilityDescription: String(localized: "CPU usage history")) { String(format: "%.0f%%", $0) }
                        .frame(height: 110)
                    HStack(spacing: 16) {
                        Label(String(format: String(localized: "User %.0f%%"), engine.cpuUserPercent), systemImage: "person.fill")
                        Label(String(format: String(localized: "Sys %.0f%%"), engine.cpuSystemPercent), systemImage: "gearshape.fill")
                        Label(String(format: String(localized: "Idle %.0f%%"), engine.cpuIdlePercent), systemImage: "moon.fill")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    Text(String(format: String(localized: "Load avg: %.2f  %.2f  %.2f  (1 / 5 / 15 min)"), engine.loadAverages.one, engine.loadAverages.five, engine.loadAverages.fifteen))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(String(localized: "Per-core")).font(.subheadline.weight(.semibold))
                        Spacer()
                        if engine.performanceCoreCount > 0 {
                            Text(String(format: "P:%ld  E:%ld", engine.performanceCoreCount, engine.efficiencyCoreCount))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                        InfoButton(text: String(localized: "P = Performance cores (faster, higher power). E = Efficiency cores (slower, lower power). macOS assigns which core handles each workload automatically. On Intel Macs all cores are equivalent and show as Core N."))
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(engine.perCoreUsage.enumerated()), id: \.offset) { idx, usage in
                                HStack {
                                    let label: String = {
                                        guard engine.performanceCoreCount > 0 else { return String(format: String(localized: "Core %ld"), idx) }
                                        return idx < engine.performanceCoreCount ? "P\(idx)" : "E\(idx - engine.performanceCoreCount)"
                                    }()
                                    Text(label).frame(width: 40, alignment: .leading).font(.caption)
                                    ProgressView(value: usage, total: 100)
                                        .tint(idx < engine.performanceCoreCount ? MetricTheme.cpu : MetricTheme.cpu.opacity(0.55))
                                    Text(String(format: "%.0f%%", usage)).frame(width: 36).font(.caption)
                                }
                            }
                        }
                    }
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label(String(localized: "Thermal Pressure"), systemImage: "thermometer.medium")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(engine.thermalState.color)
                        Spacer()
                        InfoButton(text: String(localized: "This is the macOS thermal throttling signal — not an exact temperature reading.\n\n• Nominal: No throttling. System running normally.\n• Fair: Slight throttling may be occurring.\n• Serious: Active throttling. Performance is being reduced to cool the system.\n• Critical: Severe throttling. Immediate action recommended (close apps, remove from enclosed spaces).\n\nExact die temperatures (CPU/GPU) are not readable on Apple Silicon without a privileged kernel extension. macOS blocks SMC access for user-space apps."))
                    }
                    HStack(spacing: 8) {
                        Circle().fill(engine.thermalState.color).frame(width: 10, height: 10)
                            .accessibilityHidden(true)
                        Text(engine.thermalState.label)
                            .font(.system(size: 18, weight: .bold, design: .rounded))
                    }
                }
            }

            SectionCard {
                ProcessListView(title: String(localized: "Top CPU"), icon: "cpu", color: MetricTheme.cpu, processes: engine.topCPUProcesses, unit: "%", engine: engine)
            }
            Spacer()
        }
    }
}
