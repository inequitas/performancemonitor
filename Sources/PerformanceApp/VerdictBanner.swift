import SwiftUI
import PerformanceAppCore

/// The one-line summary at the top of the popover.
///
/// `SystemVerdict` decides what to say; this decides how it reads. The split
/// keeps the rules testable without a running app, and keeps the wording in
/// the seven-language strings file where the rest of the interface lives.
struct VerdictBanner: View {
    @ObservedObject var engine: MetricsEngine

    private var verdict: SystemVerdict {
        SystemVerdict.evaluate(
            SystemVerdict.Input(
                cpuPercent: engine.cpuUsagePercent,
                memoryUsedGB: engine.memoryUsedGB,
                memoryTotalGB: engine.memoryTotalGB,
                swapUsedGB: engine.swapUsedGB,
                diskFreeGB: engine.diskFreeGB,
                thermalLevel: Self.level(engine.thermalState),
                // Only the CPU list is consulted, and only when it happens to
                // be populated. It is gated on a window being open, so most of
                // the time this is nil and the verdict falls back to the
                // unattributed wording rather than reaching for a sample.
                topProcess: engine.topCPUProcesses.first.map { ($0.name, $0.value) }
            )
        )
    }

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffectsRemoved()
            Text(sentence)
                .font(.caption)
                .foregroundStyle(verdict.isNoteworthy ? .primary : .secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(tint.opacity(verdict.isNoteworthy ? 0.12 : 0.06),
                    in: RoundedRectangle(cornerRadius: 10))
        // The popover redraws on every tick; animating the tint or the symbol
        // as values cross a threshold would flicker.
        .transaction { $0.animation = nil }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Wording

    private var sentence: String {
        switch verdict {
        case .allQuiet:
            return String(localized: "All quiet.")

        case let .throttling(serious):
            return serious
                ? String(localized: "Running hot, so macOS is slowing things down to cool off.")
                : String(localized: "Warm enough that macOS has started slowing things down.")

        case let .swapping(gb):
            return String(format: String(localized: "Out of memory, so %.1f GB has moved to disk. That is what makes a Mac feel slow."), gb)

        case let .busyProcess(name, percent):
            // The glossary knows the readable name for the processes worth
            // naming; anything else is shown as reported.
            let shown = GlossaryStore.shared.entry(for: name)?.title ?? name
            return String(format: String(localized: "%@ is using %.0f%% of the CPU."), shown, percent)

        case let .busy(percent):
            return String(format: String(localized: "CPU is at %.0f%%, spread across several processes."), percent)

        case let .memoryTight(percent):
            return String(format: String(localized: "Memory is %.0f%% full, but nothing has moved to disk yet."), percent)

        case let .diskAlmostFull(freeGB):
            return String(format: String(localized: "Only %.1f GB left on the startup disk."), freeGB)
        }
    }

    private var symbol: String {
        switch verdict {
        case .allQuiet:        return "checkmark.circle.fill"
        case .throttling:      return "thermometer.high"
        case .swapping:        return "memorychip"
        case .busyProcess,
             .busy:            return "cpu"
        case .memoryTight:     return "memorychip"
        case .diskAlmostFull:  return "internaldrive"
        }
    }

    private var tint: Color {
        switch verdict {
        case .allQuiet:                 return .green
        case let .throttling(serious):  return serious ? .red : .orange
        case .swapping:                 return .orange
        case .busyProcess, .busy:       return .blue
        case .memoryTight:              return .yellow
        case .diskAlmostFull:           return .orange
        }
    }

    private static func level(_ state: ProcessInfo.ThermalState) -> Int {
        switch state {
        case .nominal:  return 0
        case .fair:     return 1
        case .serious:  return 2
        case .critical: return 3
        @unknown default: return 0
        }
    }
}
