import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

/// Read-only look-back window over the tiered on-disk history store
/// (`HistoryDatabase`, roadmap 1.3a part 1). One card per metric, each with
/// an avg line plus a min/max band, over a user-selectable period. Opened
/// from the History tab in Settings via `openWindow(id: "history")`.
struct HistoryWindow: View {
    @ObservedObject var engine: MetricsEngine
    @Environment(\.openSettings) private var openSettings

    @State private var period: HistoryPeriod = .hours24
    @State private var samplesByMetric: [HistoryMetric: [HistorySampleRow]] = [:]
    @State private var isLoading = false

    // "This Week" overview (roadmap 1.3b) — always the trailing 7 days,
    // independent of the chart period picker above.
    @State private var weeklyMetricSummaries: [HistoryMetric: WeeklyMetricSummary] = [:]
    @State private var weeklyDataUsage: DataUsageTotals = .zero
    private let weeklyWindow: TimeInterval = 7 * 86_400

    private struct LoadKey: Equatable { let period: HistoryPeriod; let enabled: Bool }

    private var hasAnyData: Bool { samplesByMetric.values.contains { !$0.isEmpty } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 560, idealHeight: 640)
        .navigationTitle(String(localized: "History"))
        .background(.regularMaterial)
        .background(HistoryWindowFocuser(settings: engine.settings))
        .preferredColorScheme(engine.settings.preferredColorScheme)
        .task(id: LoadKey(period: period, enabled: engine.settings.persistHistoryEnabled)) {
            guard engine.settings.persistHistoryEnabled else { return }
            await loadAll()
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                if Task.isCancelled { break }
                await loadAll(silent: true)
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        if !engine.settings.persistHistoryEnabled {
            emptyState(message: String(format: String(localized: "Enable \"%@\" in Settings to record history."), String(localized: "Save history to disk")), showSettingsButton: true)
        } else if isLoading && samplesByMetric.isEmpty {
            Spacer()
            ProgressView(String(localized: "Loading…"))
            Spacer()
        } else if !hasAnyData {
            emptyState(message: String(localized: "No data captured."), showSettingsButton: false)
        } else {
            ScrollView {
                VStack(spacing: 12) {
                    WeeklySummaryCard(metricSummaries: weeklyMetricSummaries, dataUsage: weeklyDataUsage)
                    ForEach(historyMetrics) { info in
                        HistoryChartCard(info: info, period: period, samples: samplesByMetric[info.metric] ?? [])
                    }
                }
                .padding(14)
            }
        }
    }

    private var header: some View {
        HStack {
            Picker(String(localized: "Period"), selection: $period) {
                ForEach(HistoryPeriod.allCases) { p in
                    Text(p.label).tag(p)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(maxWidth: 340)
            Spacer()
            Button {
                Task { await loadAll() }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.plain)
            .disabled(!engine.settings.persistHistoryEnabled)
            .help(String(localized: "Refresh"))
        }
        .padding(14)
    }

    @ViewBuilder
    private func emptyState(message: String, showSettingsButton: Bool) -> some View {
        Spacer()
        VStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .font(.system(size: 32))
                .foregroundStyle(.secondary)
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
            if showSettingsButton {
                Button(String(localized: "Go to Settings")) {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                    openSettings()
                }
                .buttonStyle(.bordered)
            }
        }
        Spacer()
    }

    private func loadAll(silent: Bool = false) async {
        if !silent { isLoading = true }
        let now = Date()
        let from = now.addingTimeInterval(-period.duration)
        var result: [HistoryMetric: [HistorySampleRow]] = [:]
        for info in historyMetrics {
            result[info.metric] = await engine.historyDB.samples(metric: info.metric, from: from, to: now)
        }
        samplesByMetric = result
        await loadWeeklySummary(now: now, currentPeriodResult: result)
        isLoading = false
    }

    /// Always covers the trailing 7 days, regardless of the selected chart
    /// `period` — reuses this load's own rows when `period` already is
    /// "7 Days" rather than re-querying.
    private func loadWeeklySummary(now: Date, currentPeriodResult: [HistoryMetric: [HistorySampleRow]]) async {
        let from = now.addingTimeInterval(-weeklyWindow)
        var summaries: [HistoryMetric: WeeklyMetricSummary] = [:]
        for info in historyMetrics {
            let rows: [HistorySampleRow]
            if period == .days7 {
                rows = currentPeriodResult[info.metric] ?? []
            } else {
                rows = await engine.historyDB.samples(metric: info.metric, from: from, to: now)
            }
            let aggregates = rows.map { HistoryAggregate(bucketStart: $0.date, min: $0.min, avg: $0.avg, max: $0.max) }
            if let summary = WeeklySummary.metricSummary(aggregates) {
                summaries[info.metric] = summary
            }
        }
        weeklyMetricSummaries = summaries
        weeklyDataUsage = DataUsageAggregation.lastNDays(engine.dataUsage.dailyUsage, count: 7, now: now)
    }
}

typealias HistorySampleRow = (date: Date, min: Double, avg: Double, max: Double)

// MARK: - Period

enum HistoryPeriod: String, CaseIterable, Identifiable {
    case hour1, hours24, days7, days30
    var id: String { rawValue }

    var duration: TimeInterval {
        switch self {
        case .hour1:   return 3_600
        case .hours24: return 24 * 3_600
        case .days7:   return 7 * 86_400
        case .days30:  return 30 * 86_400
        }
    }

    var label: String {
        switch self {
        case .hour1:   return String(localized: "1 Hour")
        case .hours24: return String(localized: "24 Hours")
        case .days7:   return String(localized: "7 Days")
        case .days30:  return String(localized: "30 Days")
        }
    }

    var axisFormat: Date.FormatStyle {
        switch self {
        case .hour1, .hours24: return .dateTime.hour().minute()
        case .days7, .days30:  return .dateTime.month(.abbreviated).day()
        }
    }
}

// MARK: - Metric metadata

private struct HistoryMetricInfo: Identifiable {
    let metric: HistoryMetric
    let title: String
    let icon: String
    let color: Color
    let formatter: (Double) -> String
    var id: String { metric.rawValue }
}

private let historyMetrics: [HistoryMetricInfo] = [
    HistoryMetricInfo(metric: .cpuUsagePercent, title: String(localized: "CPU"), icon: "cpu", color: MetricTheme.cpu, formatter: { String(format: "%.0f%%", $0) }),
    HistoryMetricInfo(metric: .memoryUsedPercent, title: String(localized: "Memory"), icon: "memorychip", color: MetricTheme.memory, formatter: { String(format: "%.0f%%", $0) }),
    HistoryMetricInfo(metric: .gpuUsagePercent, title: String(localized: "GPU"), icon: "cube.transparent", color: MetricTheme.gpu, formatter: { String(format: "%.0f%%", $0) }),
    HistoryMetricInfo(metric: .downloadSpeedKBps, title: String(localized: "Download"), icon: "arrow.down.circle", color: MetricTheme.networkDown, formatter: formatSpeed),
    HistoryMetricInfo(metric: .uploadSpeedKBps, title: String(localized: "Upload"), icon: "arrow.up.circle", color: MetricTheme.networkUp, formatter: formatSpeed),
    HistoryMetricInfo(metric: .diskReadKBps, title: String(localized: "Disk Read"), icon: "arrow.down.doc", color: MetricTheme.disk, formatter: formatSpeed),
    HistoryMetricInfo(metric: .diskWriteKBps, title: String(localized: "Disk Write"), icon: "arrow.up.doc", color: .purple, formatter: formatSpeed),
]

// MARK: - Weekly summary card (roadmap 1.3b)

/// Compact "This Week" overview: one avg/peak line per history metric plus
/// the week's total data usage, always covering the trailing 7 days
/// regardless of the chart period picker above it.
private struct WeeklySummaryCard: View {
    let metricSummaries: [HistoryMetric: WeeklyMetricSummary]
    let dataUsage: DataUsageTotals

    private var hasAnyData: Bool { !metricSummaries.isEmpty || dataUsage != .zero }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                Label(String(localized: "7 Days"), systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                if !hasAnyData {
                    Text(String(localized: "No data captured."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(historyMetrics) { info in
                        if let summary = metricSummaries[info.metric] {
                            metricLine(info: info, summary: summary)
                        }
                    }
                    if dataUsage != .zero {
                        dataUsageLine
                    }
                }
            }
        }
    }

    private func metricLine(info: HistoryMetricInfo, summary: WeeklyMetricSummary) -> some View {
        HStack(spacing: 6) {
            Image(systemName: info.icon)
                .foregroundStyle(info.color)
                .frame(width: 16)
            Text(String(format: String(localized: "%@ — avg %@, peak %@ (%@)"),
                        info.title,
                        info.formatter(summary.average),
                        info.formatter(summary.peak),
                        summary.peakAt.formatted(.dateTime.weekday(.abbreviated).hour().minute())))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var dataUsageLine: some View {
        HStack(spacing: 6) {
            Image(systemName: "chart.bar.doc.horizontal")
                .foregroundStyle(.secondary)
                .frame(width: 16)
            Text(String(localized: "Data Usage"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Label(NetworkFormatting.formatDataUsage(bytes: dataUsage.downloadBytes), systemImage: "arrow.down")
                .font(.caption.monospacedDigit())
                .foregroundStyle(MetricTheme.networkDown)
            Label(NetworkFormatting.formatDataUsage(bytes: dataUsage.uploadBytes), systemImage: "arrow.up")
                .font(.caption.monospacedDigit())
                .foregroundStyle(MetricTheme.networkUp)
        }
    }
}

// MARK: - Chart card

private struct HistoryChartCard: View {
    let info: HistoryMetricInfo
    let period: HistoryPeriod
    let samples: [HistorySampleRow]

    private var latest: Double? { samples.last?.avg }

    var body: some View {
        SectionCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(info.title, systemImage: info.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(info.color)
                    Spacer()
                    if let latest {
                        Text(info.formatter(latest))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                if samples.isEmpty {
                    Text(String(localized: "No data captured."))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 90)
                } else {
                    Chart(samples, id: \.date) { s in
                        AreaMark(
                            x: .value("Time", s.date),
                            yStart: .value("Min", s.min),
                            yEnd: .value("Max", s.max)
                        )
                        .foregroundStyle(info.color.opacity(0.18))
                        LineMark(
                            x: .value("Time", s.date),
                            y: .value("Avg", s.avg)
                        )
                        .foregroundStyle(info.color)
                        .interpolationMethod(.monotone)
                    }
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                            AxisGridLine()
                            AxisValueLabel(format: period.axisFormat)
                        }
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                            AxisGridLine()
                            AxisValueLabel {
                                if let v = value.as(Double.self) {
                                    Text(info.formatter(v)).font(.caption2)
                                }
                            }
                        }
                    }
                    .frame(height: 110)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(String(format: String(localized: "%@ history"), info.title))
                }
            }
        }
    }
}

// MARK: - Window focus / activation-policy helper
//
// Mirrors SettingsView's private WindowFocuser: makes the window key on
// open, and restores the .accessory activation policy on close (when
// "Show in Dock" is off and no other titled window remains visible).

private struct HistoryWindowFocuser: NSViewRepresentable {
    let settings: SettingsStore

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NotificationCenter.default.addObserver(
                forName: NSWindow.willCloseNotification,
                object: window,
                queue: .main
            ) { [weak settings] _ in
                Task { @MainActor in
                    guard let settings, !settings.showInDock else { return }
                    if !NSApp.hasOtherVisibleTitledWindow(besides: window) {
                        NSApp.setActivationPolicy(.accessory)
                    }
                }
            }
        }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}
