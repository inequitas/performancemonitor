import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

// MARK: - Disk

private struct DiskButterflyChart: View {
    let readHistory:  [Double]
    let writeHistory: [Double]
    let readSpeed:    Double
    let writeSpeed:   Double

    private var sharedMax: Double { absoluteMax(readHistory, writeHistory) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label(formatSpeed(readSpeed), systemImage: "arrow.down")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.indigo)
                Text("Read").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("Write").font(.caption).foregroundStyle(.secondary)
                Label(formatSpeed(writeSpeed), systemImage: "arrow.up")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.purple)
            }
            HStack(spacing: 4) {
                VStack(spacing: 0) {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(formatSpeed(sharedMax)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSpeed(sharedMax / 2)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                    }
                    .frame(height: 90)
                    Text(formatSpeed(0)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .frame(height: 14)
                    VStack(alignment: .trailing, spacing: 0) {
                        Spacer()
                        Text(formatSpeed(sharedMax / 2)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        Spacer()
                        Text(formatSpeed(sharedMax)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(height: 90)
                }
                .frame(width: 56)
                VStack(spacing: 0) {
                    MetricChart(values: readHistory, fixedMax: sharedMax, showAxes: false, showGridLines: true, fillFrame: true, color: .indigo, style: .area, accessibilityDescription: "Disk read speed history") { formatSpeed($0) }
                        .frame(height: 90)
                    Color.primary.opacity(0.25).frame(height: 1).frame(height: 14)
                    MetricChart(values: writeHistory, fixedMax: sharedMax, showAxes: false, showGridLines: true, fillFrame: true, color: .purple, style: .area, accessibilityDescription: "Disk write speed history") { formatSpeed($0) }
                        .frame(height: 90)
                        .scaleEffect(y: -1)
                }
                .frame(height: 194)
            }
        }
    }
}

struct DiskDetailView: View {
    @ObservedObject var engine: MetricsEngine

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Disk", systemImage: MetricsEngine.Panel.disk.icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(MetricTheme.disk)

            SectionCard {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Storage").font(.subheadline.weight(.semibold))
                        Spacer()
                        if let smart = engine.diskSmartStatus {
                            let ok = smart == "Verified"
                            Label(ok ? "SMART OK" : smart, systemImage: ok ? "checkmark.shield.fill" : "exclamationmark.shield.fill")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(ok ? .green : .red)
                        }
                    }
                    if let wear = engine.diskWearInfo {
                        NVMeWearRow(wear: wear)
                    }
                    let visibleVolumes = engine.volumes.filter { engine.settings.showRemovableVolumes || !$0.isRemovable }
                    ForEach(visibleVolumes) { volume in
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Text(volume.name).font(.caption).lineLimit(1)
                                if volume.isRemovable { Text("Removable").font(.caption2).foregroundStyle(.secondary) }
                            }
                            DiskUsageBar(used: volume.totalGB - volume.freeGB, total: volume.totalGB)
                            HStack {
                                Text(String(format: "%.1f GB used", volume.totalGB - volume.freeGB))
                                    .font(.caption2).foregroundStyle(.secondary)
                                Spacer()
                                Text(String(format: "%.1f GB free", volume.freeGB))
                                    .font(.caption2).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            SectionCard {
                DiskButterflyChart(
                    readHistory:  engine.diskReadHistory,
                    writeHistory: engine.diskWriteHistory,
                    readSpeed:    engine.diskReadKBps,
                    writeSpeed:   engine.diskWriteKBps
                )
            }

            Spacer()
        }
    }
}

// MARK: - NVMe wear level

/// Shows wear %, total bytes written, and power-on hours for the internal
/// SSD, read via IOKit's `IONVMeSMARTInterface` (no root required). Only
/// rendered when `engine.diskWearInfo` is non-nil — external/older drives
/// without a matching IOKit class simply don't show this row.
private struct NVMeWearRow: View {
    let wear: NVMeWearInfo

    var body: some View {
        HStack {
            Label("\(wear.percentageUsed)% wear", systemImage: "battery.75percent")
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text(String(format: "%.1f TB written", wear.totalBytesWrittenTB))
                .font(.caption2).foregroundStyle(.secondary)
            Spacer()
            Text("\(wear.powerOnHours) h on")
                .font(.caption2).foregroundStyle(.secondary)
        }
    }
}

// MARK: - Disk storage helpers

private struct DiskUsageBar: View {
    let used: Double
    let total: Double

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(Color.indigo)
                    .frame(width: max(2, geo.size.width * used / max(total, 1)))
                Rectangle()
                    .fill(Color.gray.opacity(0.15))
            }
        }
        .frame(height: 14)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Color.primary.opacity(0.08), lineWidth: 0.5))
    }
}
