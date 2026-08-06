import SwiftUI
import PerformanceAppCore

/// The summary line at the top of the popover.
///
/// Collapsed it says how many things are worth a look, or that nothing is.
/// Expanded it lists them, and each row opens the window that explains it
/// further, because "3.7 GB has moved to disk" is a statement the reader can do
/// nothing with unless they can get to the memory view from it.
///
/// `SystemVerdict` decides what is true; this decides how it reads and where it
/// goes. The split keeps the rules testable without a running app and keeps the
/// wording in the seven-language strings file with the rest of the interface.
struct VerdictBanner: View {
    @ObservedObject var engine: MetricsEngine
    let openPanel: (MetricsEngine.Panel) -> Void

    @State private var expanded = false

    private var findings: [SystemFinding] {
        // The same input the Shortcuts action reads, so the popover and an
        // automation can never tell different stories about the same machine.
        SystemVerdict.evaluate(engine.verdictInput)
    }

    var body: some View {
        let found = findings
        VStack(alignment: .leading, spacing: 0) {
            // A single finding is shown in full straight away. Hiding one line
            // behind "1 thing worth a look" costs a click and tells the reader
            // nothing they did not already see. Summarising only earns its keep
            // once there are several.
            if found.count == 1 {
                findingRow(found[0])
            } else {
                summaryRow(found)
                if expanded, !found.isEmpty {
                    Divider().padding(.horizontal, 12)
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(found) { finding in
                            findingRow(finding)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }
        }
        .background(tint(for: found).opacity(found.isEmpty ? 0.06 : 0.12),
                    in: RoundedRectangle(cornerRadius: 10))
        // The popover redraws every tick; animating as values cross a threshold
        // would flicker.
        .transaction { $0.animation = nil }
    }

    // MARK: - Summary

    @ViewBuilder
    private func summaryRow(_ found: [SystemFinding]) -> some View {
        let content = HStack(spacing: 7) {
            Image(systemName: found.isEmpty ? "checkmark.circle.fill" : symbol(for: found[0].kind))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint(for: found))
                .symbolEffectsRemoved()
            Text(summary(found))
                .font(.caption)
                .foregroundStyle(found.isEmpty ? .secondary : .primary)
            Spacer(minLength: 0)
            if !found.isEmpty {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
                    .rotationEffect(.degrees(expanded ? 90 : 0))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .contentShape(Rectangle())

        if found.isEmpty {
            content
        } else {
            Button { expanded.toggle() } label: { content }
                .buttonStyle(.plain)
                .help(expanded ? String(localized: "Hide details") : String(localized: "Show details"))
        }
    }

    private func summary(_ found: [SystemFinding]) -> String {
        // count == 1 never reaches here; that case is shown in full instead.
        found.isEmpty
            ? String(localized: "All quiet.")
            : String(format: String(localized: "%ld things worth a look."), found.count)
    }

    // MARK: - Detail rows

    private func findingRow(_ finding: SystemFinding) -> some View {
        Button {
            openPanel(panel(for: finding.topic))
        } label: {
            HStack(alignment: .top, spacing: 7) {
                Image(systemName: symbol(for: finding.kind))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(tint(for: finding.severity))
                    .frame(width: 13)
                    .padding(.top, 1)
                    .symbolEffectsRemoved()
                VStack(alignment: .leading, spacing: 3) {
                    Text(FindingWording.sentence(for: finding.kind))
                        .font(.caption)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(FindingWording.advice(for: finding.kind))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 4)
                Image(systemName: "arrow.up.forward.square")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(String(format: String(localized: "Open %@"), panel(for: finding.topic).title))
    }

    // MARK: - Presentation

    private func symbol(for kind: SystemFinding.Kind) -> String {
        switch kind {
        case .throttling:                 return "thermometer.high"
        case .swapping, .memoryTight:     return "memorychip"
        case .busyProcess, .busy:         return "cpu"
        case .diskAlmostFull:             return "internaldrive"
        }
    }

    private func tint(for severity: SystemFinding.Severity) -> Color {
        switch severity {
        case .serious: return .red
        case .warning: return .orange
        case .notable: return .blue
        }
    }

    private func tint(for found: [SystemFinding]) -> Color {
        guard let worst = found.first else { return .green }
        return tint(for: worst.severity)
    }

    private func panel(for topic: SystemFinding.Topic) -> MetricsEngine.Panel {
        switch topic {
        case .cpu:     return .cpu
        case .memory:  return .memory
        case .disk:    return .disk
        case .thermal: return .thermal
        }
    }

}
