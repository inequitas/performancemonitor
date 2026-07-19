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
                Label("Memory", systemImage: MetricsEngine.Panel.memory.icon)
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(MetricTheme.memory)
                Spacer()
                ChartStylePicker(style: $style)
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text("\(String(format: "%.2f", engine.memoryUsedGB)) GB / \(String(format: "%.2f", engine.memoryTotalGB)) GB")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .foregroundStyle(MetricTheme.memory)
                    MetricChart(values: engine.memoryHistory, unit: "GB", fixedMax: max(engine.memoryTotalGB, 1), color: MetricTheme.memory, style: style, accessibilityDescription: "Memory usage history") { String(format: "%.1f GB", $0) }
                        .frame(height: 110)
                    HStack(spacing: 4) {
                        HStack(spacing: 16) {
                            Label(String(format: "App %.1fGB", engine.memoryAppGB), systemImage: "app.fill")
                            Label(String(format: "Wired %.1fGB", engine.memoryWiredGB), systemImage: "lock.fill")
                            Label(String(format: "Cmp %.1fGB", engine.memoryCompressedGB), systemImage: "archivebox.fill")
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        InfoButton(text: "App: Active + inactive pages — memory currently in use or recently used by apps.\n\nWired: Locked in RAM by the kernel and drivers. Cannot be paged out to disk.\n\nCompressed: Pages compressed by macOS memory pressure system to free up physical RAM. High compressed memory is normal; it becomes swap when compression is no longer enough.\n\nSwap: Data written to disk because RAM was full. Persistent high swap usage indicates you need more RAM.")
                    }
                    Text("Swap used: \(String(format: "%.2f", engine.swapUsedGB)) GB")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }

            SectionCard {
                ProcessListView(title: "Top Memory", icon: "memorychip", color: MetricTheme.memory, processes: engine.topMemoryProcesses, unit: "%", engine: engine)
            }
            Spacer()
        }
    }
}
