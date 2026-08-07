import AppKit
import SwiftUI
import PerformanceAppCore

/// A small always-on-top readout, for when the thing you are watching is
/// full-screen: a game, a render, a long build.
///
/// The menu bar disappears in full screen and the popover cannot be opened
/// without leaving what you are doing, which is exactly when someone most wants
/// to see the temperature. A floating panel is the only thing that survives
/// that.
///
/// It is an `NSPanel` with `.nonactivatingPanel`, so clicking or dragging it
/// does not pull focus away from the game. `.canJoinAllSpaces` plus
/// `.fullScreenAuxiliary` is what keeps it visible over full-screen windows;
/// without the latter macOS hides it the moment anything goes full screen,
/// which would defeat the point.
///
/// Hidden, it holds no SwiftUI tree at all. That is the same discipline the
/// popover and the detail windows follow: a view that observes the engine keeps
/// it publishing to something, and this one would otherwise be observing for
/// hours while nobody looks.
///
/// Visible it costs about a percentage point of a core and some 12 MB, measured
/// against the same build with it hidden. That is a redraw per tick of a live
/// readout, roughly what an open detail window costs, and it only happens while
/// somebody is looking at it. The blurred background was the obvious suspect
/// and was measured: a flat colour came out at 2.39% against the material's
/// 2.40%, so it is the SwiftUI pass itself, not the blur, and the better
/// looking option is free.
@MainActor
final class FloatingDashboardController: NSObject, NSWindowDelegate {
    private weak var engine: MetricsEngine?
    private var panel: NSPanel?

    /// Where the panel was last left, so it comes back where it was put rather
    /// than in the middle of the screen every time.
    private static let frameKey = "floatingDashboardFrame"
    /// Whether it was open when the app last quit.
    private static let visibleKey = "floatingDashboardVisible"

    private(set) var isVisible = false

    init(engine: MetricsEngine) {
        self.engine = engine
        super.init()
        guard UserDefaults.standard.bool(forKey: Self.visibleKey) else { return }
        // Not here and now. This runs while the App's scene body is being
        // evaluated for the first time, and building a hosting view inside that
        // evaluation trips SwiftUI's own graph: it aborts in
        // NSHostingView.layout(). One turn of the run loop later the app exists
        // and the same call is fine. Found by crashing on every launch, which a
        // persisted "was open" flag turns into a loop.
        DispatchQueue.main.async { [weak self] in self?.show() }
    }

    func toggle() { isVisible ? hide() : show() }

    func show() {
        guard let engine else { return }
        let panel = self.panel ?? makePanel()
        self.panel = panel

        let host = NSHostingController(rootView: FloatingDashboardView(engine: engine))
        host.view.layoutSubtreeIfNeeded()
        panel.contentViewController = host
        panel.setContentSize(host.view.fittingSize)
        restoreFrame(panel)
        // orderFrontRegardless, not makeKeyAndOrderFront: showing a readout
        // should never take focus from whatever is being watched.
        panel.orderFrontRegardless()

        isVisible = true
        UserDefaults.standard.set(true, forKey: Self.visibleKey)
    }

    func hide() {
        saveFrame()
        panel?.orderOut(nil)
        // Releasing the tree is the point, not tidiness: while it exists it
        // observes every tick.
        panel?.contentViewController = nil
        isVisible = false
        UserDefaults.standard.set(false, forKey: Self.visibleKey)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 190, height: 120),
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered,
                            defer: false)
        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        // Without .fullScreenAuxiliary the panel vanishes over a full-screen
        // game, which is the case it exists for.
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.delegate = self
        return panel
    }

    private func restoreFrame(_ panel: NSPanel) {
        guard let saved = UserDefaults.standard.string(forKey: Self.frameKey) else {
            panel.center()
            return
        }
        panel.setFrameOrigin(NSRectFromString(saved).origin)
        // A display can be unplugged between sessions, which would otherwise
        // leave the panel parked off-screen with no way to reach it.
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(panel.frame) }) {
            panel.center()
        }
    }

    private func saveFrame() {
        guard let panel, panel.isVisible else { return }
        UserDefaults.standard.set(NSStringFromRect(panel.frame), forKey: Self.frameKey)
    }

    func windowDidMove(_ notification: Notification) { saveFrame() }
}

// MARK: - Contents

/// Deliberately not the popover's cards. Those are sized to be read at leisure;
/// this is glanced at from the corner of an eye while doing something else, so
/// it is one line per metric and nothing that moves on its own.
private struct FloatingDashboardView: View {
    @ObservedObject var engine: MetricsEngine
    @State private var hovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            row("cpu", MetricTheme.cpu, String(localized: "CPU"),
                String(format: "%.0f%%", engine.cpuUsagePercent))
            row("memorychip", MetricTheme.memory, String(localized: "Memory"),
                String(format: "%.1f GB", engine.memoryUsedGB))
            row("rectangle.3.group", MetricTheme.gpu, String(localized: "GPU"),
                String(format: "%.0f%%", engine.gpuUsagePercent))
            if let temperature = engine.cpuTemperatureC {
                row("thermometer.medium", MetricTheme.temperature, String(localized: "Temperature"),
                    String(format: "%.0f °C", temperature))
            }
            row("network", MetricTheme.networkDown, String(localized: "Network"),
                "↓\(NetworkFormatting.formatSpeed(kbps: engine.downloadSpeedKBps))")
        }
        .padding(.vertical, 9)
        .padding(.horizontal, 11)
        .frame(width: 190, alignment: .leading)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.10)))
        // The close button only appears on hover: a permanent one is one more
        // thing in the corner of your eye, and this panel exists to be ignored
        // until it is not.
        .overlay(alignment: .topTrailing) {
            if hovering {
                Button {
                    engine.floatingDashboard?.hide()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(5)
                .help(String(localized: "Hide the floating panel"))
            }
        }
        .onHover { hovering = $0 }
        // The values change every tick; animating them would make a panel meant
        // to sit still twitch.
        .transaction { $0.animation = nil }
    }

    private func row(_ icon: String, _ tint: Color, _ label: String, _ value: String) -> some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundStyle(tint)
                .frame(width: 13)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer(minLength: 6)
            Text(value)
                .font(.caption.monospacedDigit().weight(.medium))
        }
    }
}
