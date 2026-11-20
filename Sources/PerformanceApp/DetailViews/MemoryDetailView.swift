import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

// MARK: - Memory

struct MemoryDetailView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var style: ChartDisplayStyle = .area

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label(String(localized: "Memory"), systemImage: MetricsEngine.Panel.memory.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MetricTheme.memory)
                Spacer()
                ChartStylePicker(style: $style)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(String(format: String(localized: "%@ GB / %@ GB"), String(format: "%.2f", engine.memoryUsedGB), String(format: "%.2f", engine.memoryTotalGB)))
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(MetricTheme.memory)
                    MetricChart(values: engine.memoryHistory, unit: "GB", fixedMax: max(engine.memoryTotalGB, 1), color: MetricTheme.memory, style: style, accessibilityDescription: String(localized: "Memory usage history")) { String(format: "%.1f GB", $0) }
                        .frame(height: 110)
                    HStack(spacing: 4) {
                        HStack(spacing: 16) {
                            Label(String(format: String(localized: "App %.1fGB"), engine.memoryAppGB), systemImage: "app.fill")
                            Label(String(format: String(localized: "Wired %.1fGB"), engine.memoryWiredGB), systemImage: "lock.fill")
                            Label(String(format: String(localized: "Cmp %.1fGB"), engine.memoryCompressedGB), systemImage: "archivebox.fill")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        InfoButton(text: String(localized: "Used: App + Wired + Compressed. Reclaimable file cache is excluded.\n\nApp: Anonymous memory minus purgeable pages.\n\nWired: Memory locked in RAM by the kernel and drivers.\n\nCompressed: Physical RAM used to store compressed pages.\n\nSwap: Memory stored on disk. Swap in use alone does not mean RAM is currently under pressure."))
                    }
                    Text(String(format: String(localized: "Swap used: %@ GB"), String(format: "%.2f", engine.swapUsedGB)))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SectionCard {
                ProcessListView(title: String(localized: "Top Memory"), icon: "memorychip", color: MetricTheme.memory, processes: engine.topMemoryProcesses, unit: "%", engine: engine)
            }
            Spacer()
        }
    }
}
