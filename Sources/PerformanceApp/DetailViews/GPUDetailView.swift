import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

// MARK: - GPU & Displays

private func displayIcon(_ display: DisplayInfo) -> String {
    if display.isBuiltIn { return "laptopcomputer" }
    let ratio = Double(display.width) / Double(display.height)
    if ratio >= 2.3 { return "rectangle.ratio.16.to.9.fill" }
    return "display"
}

struct GPUDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Label("GPU & Displays", systemImage: "cube.transparent")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(.cyan)
                Spacer()
                InfoButton(text: "GPU utilization percentage is not available through any public macOS API on Apple Silicon. Apple's IOKit SMC interface blocks access to GPU load counters for user-space processes.\n\nThird-party tools that show GPU % use private, entitled APIs or kernel extensions that require special signing. The Metal information shown here (working set size, power mode) is the maximum available through the public API.")
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    Text(engine.gpuName)
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundStyle(.cyan)
                    detailRow("Location", engine.gpuLocation)
                    detailRow("Max working set", String(format: "%.1f GB", engine.gpuRecommendedMemoryGB))
                    detailRow("Power mode", engine.gpuIsLowPower ? "Low power" : "High performance")
                }
            }

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Displays").font(.subheadline.weight(.semibold))
                        Spacer()
                        Button {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Displays-Settings.extension")!)
                        } label: {
                            Label("Arrange…", systemImage: "rectangle.3.group")
                                .font(.caption)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                    }
                    if engine.displays.isEmpty {
                        Text("No display info available")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(engine.displays) { info in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(alignment: .top, spacing: 8) {
                                Image(systemName: displayIcon(info))
                                    .font(.system(size: 15))
                                    .foregroundStyle(.cyan.opacity(0.8))
                                    .frame(width: 20)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(info.name).font(.caption.weight(.medium))
                                    Text("\(info.width) × \(info.height)  @\(info.refreshRateHz) Hz  (\(info.scaleFactor == 2 ? "Retina" : String(format: "%.0f×", info.scaleFactor)))")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)
                                    if !info.colorProfile.isEmpty {
                                        Text(info.colorProfile)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                    if !info.connectionType.isEmpty {
                                        Text(info.connectionType)
                                            .font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 3) {
                                    if info.isMain {
                                        Text("Main")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.cyan.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.cyan)
                                    }
                                    if info.trueTone {
                                        Text("True Tone")
                                            .font(.caption2)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.yellow.opacity(0.15), in: Capsule())
                                            .foregroundStyle(.yellow)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Spacer()
        }
    }

}
