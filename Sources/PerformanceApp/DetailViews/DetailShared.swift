import SwiftUI
import AppKit
import Charts
import PerformanceAppCore

// Once a detail window has been opened, SwiftUI keeps its view tree alive after
// the window closes, and that tree stays subscribed to the engine's ~80
// @Published writes per second — so a window nobody can see keeps re-evaluating
// its body forever. Same pattern as the popover, fixed in 15afcd6 (see
// ExtraMenuBarController.mountPopoverContent / popoverDidClose).
//
// This was measured on 23 Jul and deliberately left alone: 6.5% after
// open/close vs 6.9% with nothing ever opened, i.e. lost in the noise. That
// call was right at the time and wrong a few hours later — `518f968` landed the
// same evening and took the idle floor from 5.3% to 2.5%. Re-measured 28 Jul
// against the lower floor, the same absolute cost is now the dominant one:
//
//     never opened a window       1.76% CPU / 78 MB
//     after one open + close      4.25% CPU / 108 MB   (and it never drops back)
//
// Confirmed with `sample <pid> 20` while CGWindowListCopyWindowInfo reported
// zero on-screen windows: the profile still contained MemoryDetailView.body
// .getter over Combine's Published.subscript.getter. The old comment ended with
// "revisit only if a future change makes this measurable" — this is that revisit.
//
// The fix is to unmount the content while the window is not visible. The old
// worry was that a reopened window would come back empty or mis-sized, since
// makeNSView runs once per window instance and SwiftUI reuses the window. That
// is handled by construction: the window's size comes from the outer .frame
// below (and from setContentSize in WindowFloatAccessor), never from the
// content, and the placeholder keeps the scroll content's height stable, so
// there is nothing left to collapse.
struct DetailWindow: View {
    let kind: MetricsEngine.Panel
    @ObservedObject var engine: MetricsEngine

    /// Mirrors the window's real on-screen visibility, driven by
    /// `WindowFloatAccessor` from the same occlusion/close events that already
    /// gate ps/nettop sampling. While false, the content tree is torn down and
    /// stops observing the engine entirely.
    @State private var isContentVisible = true

    var body: some View {
        ScrollView {
            Group {
                if isContentVisible {
                    switch kind {
                    case .cpu:       CPUDetailView(engine: engine)
                    case .memory:    MemoryDetailView(engine: engine)
                    case .network:   NetworkDetailView(engine: engine)
                    case .disk:      DiskDetailView(engine: engine)
                    case .gpu:       GPUDetailView(engine: engine)
                    case .battery:   BatteryDetailView(engine: engine)
                    case .bluetooth: BluetoothDetailView(engine: engine)
                    case .thermal:   ThermalDetailView(engine: engine)
                    }
                } else {
                    // Holds the scroll content's height so nothing reflows while
                    // the real content is unmounted. Observes nothing.
                    Color.clear.frame(height: detailWindowHeight)
                }
            }
            .padding()
            .frame(width: detailWindowWidth, alignment: .leading)
        }
        .frame(width: detailWindowWidth, height: detailWindowHeight)
        .navigationTitle(kind.title)
        .background(.regularMaterial)
        .background(WindowFloatAccessor(kind: kind, engine: engine,
                                        isContentVisible: $isContentVisible))
        .preferredColorScheme(engine.settings.preferredColorScheme)
    }
}

let detailWindowWidth: CGFloat = 420
let detailWindowHeight: CGFloat = 540

func formatSpeed(_ kbps: Double) -> String {
    kbps > 1024 ? String(format: "%.2f MB/s", kbps / 1024) : String(format: "%.1f KB/s", kbps)
}

func batterySystemImage(_ pct: Int, charging: Bool = false) -> String {
    let suffix = charging ? ".bolt" : ""
    switch pct {
    case 76...: return "battery.100percent\(suffix)"
    case 51...: return "battery.75percent\(suffix)"
    case 26...: return "battery.50percent\(suffix)"
    case 11...: return "battery.25percent\(suffix)"
    default:    return "battery.0percent\(suffix)"
    }
}

func detailRow(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label).font(.caption).foregroundStyle(.secondary)
        Spacer()
        Text(value).font(.caption.monospacedDigit())
    }
}

struct EarbudBatteryPill: View {
    let label: String
    let pct: Int
    init(_ label: String, _ pct: Int) { self.label = label; self.pct = pct }
    var body: some View {
        HStack(spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.tertiary)
            Text(String(format: "%ld%%", pct)).font(.caption2.monospacedDigit()).foregroundStyle(pct < 20 ? .red : .secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(pct < 20 ? String(format: String(localized: "%ld percent, low battery"), pct) : String(format: String(localized: "%ld percent"), pct))
    }
}

// MARK: - Shared components

struct ChartStylePicker: View {
    @Binding var style: ChartDisplayStyle
    var body: some View {
        Picker("", selection: $style) {
            ForEach(ChartDisplayStyle.allCases) { s in
                Image(systemName: s.systemImage).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 110)
    }
}

struct SectionCard<Content: View>: View {
    let content: Content
    init(@ViewBuilder content: () -> Content) { self.content = content() }
    var body: some View {
        content
            .padding(12)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

struct InfoButton: View {
    let text: String
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            Text(text)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(14)
                .frame(width: 280)
        }
    }
}

// MARK: - Glossary

/// The "what is this?" affordance on a process row. Only appears for processes
/// the glossary knows about, which is deliberately a minority: an unfamiliar
/// system process is worth explaining, and an app the user installed themselves
/// is not.
private struct GlossaryButton: View {
    let processName: String
    let entry: GlossaryEntry
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            Image(systemName: entry.expectedHigh ? "checkmark.circle" : "questionmark.circle")
                .font(.caption2)
                .foregroundStyle(entry.expectedHigh ? AnyShapeStyle(Color.green.opacity(0.8)) : AnyShapeStyle(.tertiary))
        }
        .buttonStyle(.plain)
        .help(entry.title)
        .accessibilityLabel(Text(String(format: String(localized: "What is %@?"), processName)))
        .popover(isPresented: $showing, arrowEdge: .trailing) {
            VStack(alignment: .leading, spacing: 8) {
                Text(entry.title).font(.subheadline.weight(.semibold))
                if let vendor = entry.vendor {
                    Text(vendor).font(.caption2).foregroundStyle(.tertiary)
                }
                Text(entry.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if entry.expectedHigh {
                    Label(String(localized: "High usage is normal for this one."),
                          systemImage: "checkmark.circle")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
                Text(processName)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .padding(.top, 2)
            }
            .padding(14)
            .frame(width: 300, alignment: .leading)
        }
    }
}

// MARK: - Process list

struct ProcessListView: View {
    let title: String
    let icon: String
    let color: Color
    let processes: [ProcessUsage]
    let unit: String
    let engine: MetricsEngine

    @State private var pendingKill: ProcessUsage?
    @State private var paused = false
    @State private var frozenList: [ProcessUsage] = []

    private var displayed: [ProcessUsage] { paused ? frozenList : processes }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label(title, systemImage: icon)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Button {
                    if !paused { frozenList = Array(processes.prefix(engine.settings.topProcessCount)) }
                    paused.toggle()
                } label: {
                    Image(systemName: paused ? "play.circle.fill" : "pause.circle")
                        .font(.system(size: 14))
                        .foregroundStyle(paused ? color : .secondary)
                }
                .buttonStyle(.plain)
                .help(paused ? String(localized: "Resume live updates") : String(localized: "Pause list"))
            }

            if displayed.isEmpty {
                Text(paused ? String(localized: "No data captured.") : String(localized: "Loading…"))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(displayed.prefix(engine.settings.topProcessCount)) { proc in
                    let known = GlossaryStore.shared.entry(for: proc.name)
                    HStack(spacing: 6) {
                        Text(proc.name)
                            .font(.caption)
                            .lineLimit(1)
                        if let known {
                            GlossaryButton(processName: proc.name, entry: known)
                        }
                        Spacer()
                        Text(String(format: "%.1f%@", proc.value, unit))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        if proc.pid > 0 {
                            Button { pendingKill = proc } label: {
                                Image(systemName: "xmark.circle")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .help(String(format: String(localized: "Quit %@"), proc.name))
                        }
                    }
                    .contentShape(Rectangle())
                    .contextMenu {
                        if proc.pid > 0 {
                            Button(String(format: String(localized: "Quit %@"), proc.name), role: .destructive) { pendingKill = proc }
                        }
                    }
                }
            }
        }
        .alert(
            String(format: String(localized: "Quit %@?"), pendingKill?.name ?? String(localized: "process")),
            isPresented: Binding(get: { pendingKill != nil }, set: { _ in pendingKill = nil }),
            presenting: pendingKill
        ) { proc in
            Button(String(localized: "Cancel"), role: .cancel) { }
            Button(String(localized: "Quit"), role: .destructive) {
                engine.terminateProcess(pid: proc.pid)
                paused = false
            }
        } message: { proc in
            Text(String(format: String(localized: "This sends a quit signal to the process (PID %ld). Unsaved work may be lost."), Int(proc.pid)))
        }
    }
}

// MARK: - Shared helpers

// MARK: - WiFi Signal Bars

struct WiFiSignalBars: View {
    let rssi: Int   // dBm, e.g. -55

    private var bars: Int { WiFiSignal.bars(forRSSI: rssi) }

    private var label: String { WiFiSignal.label(forBars: bars) }

    private var color: Color {
        switch bars {
        case 4, 3: return .green
        case 2: return .orange
        default: return .red
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            // 4 bars of increasing height — decorative; the text alongside already
            // states the signal quality in words plus the raw dBm value.
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { i in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(i <= bars ? color : Color.secondary.opacity(0.25))
                        .frame(width: 7, height: CGFloat(i) * 5 + 4)
                }
            }
            .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Text("\(rssi) dBm")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(String(localized: "Wi-Fi signal"))
        .accessibilityValue(String(format: String(localized: "%@, %ld dBm"), label, rssi))
    }
}

struct CopyableIPRow: View {
    let icon: String
    let label: String
    let value: String
    let iconColor: Color
    @State private var copied = false

    init(icon: String = "network", label: String, value: String, iconColor: Color = .secondary) {
        self.icon = icon
        self.label = label
        self.value = value
        self.iconColor = iconColor
    }

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(iconColor)
                .frame(width: 14)
            Text(label).font(.caption).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.caption.monospacedDigit())
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(value, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
            } label: {
                Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    .font(.caption2)
                    .foregroundStyle(copied ? .green : .secondary)
            }
            .buttonStyle(.plain)
        }
    }
}

// Detail windows are standard titled windows, so opening one makes macOS show
// a Dock icon regardless of the accessory activation policy. Restore .accessory
// on close (if Show in Dock is off and this was the last visible window) the
// same way SettingsView's WindowFocuser does — otherwise opening a metric card
// permanently pins the Dock icon for the rest of the session.
//
// Also reports this window's actual on-screen visibility to the engine via
// `setPanelVisible`, so ps/nettop sampling for the CPU/Memory/Network panels
// only runs while their window is really visible (not minimized/fully
// occluded) — see `MetricsEngine.setPanelVisible`.
private struct WindowFloatAccessor: View {
    let kind: MetricsEngine.Panel
    let engine: MetricsEngine
    /// Drives `DetailWindow.isContentVisible` from the very same events that
    /// report visibility to the engine, so the content tree and the sampling
    /// gate can never disagree about whether this window is on screen.
    @Binding var isContentVisible: Bool

    var body: some View {
        WindowVisibilityAccessor(
            isVisible: $isContentVisible,
            configure: { window in
                window.level = .floating
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                // Force every detail window to exactly the same content size.
                // SwiftUI's frame/defaultSize hints are unreliable when windows
                // have been resized or when content height differs between tabs.
                window.setContentSize(NSSize(width: detailWindowWidth, height: detailWindowHeight))
                window.styleMask.remove(.resizable)
            },
            onVisibilityChange: { [weak engine] visible in
                engine?.setPanelVisible(visible, for: kind)
            },
            onClose: { [weak engine] window in
                restoreAccessoryPolicyIfLastWindow(besides: window, settings: engine?.settings)
            }
        )
    }
}
