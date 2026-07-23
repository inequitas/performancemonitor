import AppKit
import SwiftUI
import Combine
import Carbon
import PerformanceAppCore

/// Owns the single NSStatusItem that shows all enabled metrics side-by-side.
/// Subscribes to the engine's raw metric publishers and renders images itself,
/// keeping all AppKit/CoreGraphics drawing out of MetricsEngine.
@MainActor
final class ExtraMenuBarController: NSObject {
    private weak var engine: MetricsEngine?
    private let settings: SettingsStore
    private var statusItem: NSStatusItem?
    private var sharedPopover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []
    private var localMonitor: Any?
    private var hotKeyRef: EventHotKeyRef?
    private var carbonHandlerRef: EventHandlerRef?
    private var lastRenderKey: Int?

    // Global shortcut: ⌥⌘P — works system-wide to open/close the popover
    static let shortcutDisplay = "⌥⌘P"
    private static let shortcutKeyCode: UInt16 = 35   // P
    private static let shortcutFlags: NSEvent.ModifierFlags = [.option, .command]

    // Fixed font/colour attributes — allocated once, shared across all renders.
    private static let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white
    ]

    // Widest string each metric/style combo will ever produce, used to fix slot widths.
    private static let maxTextLabel: [MenuBarMetric: String] = [
        .cpu: "CPU 100%", .memory: "MEM 16.0G",
        .network: "↓9.9m ↑9.9m", .disk: "R 9999K W 9999K", .gpu: "GPU 100%"
    ]
    private static let maxTextLabelDiskSpace = "DSK 16.0G"
    private static let maxSparkLabel: [MenuBarMetric: String] = [
        .cpu: "100%", .memory: "16.0G", .network: "9.9m", .disk: "16.0G", .gpu: "100%"
    ]
    // Pre-measured widths so NSString.size() is never called at render time.
    private static let textSlotW: [MenuBarMetric: CGFloat] = {
        let a = attrs
        var d = Dictionary(uniqueKeysWithValues: maxTextLabel.map { metric, s in
            (metric, ceil((s as NSString).size(withAttributes: a).width))
        })
        d[.disk] = max(d[.disk] ?? 0, ceil((maxTextLabelDiskSpace as NSString).size(withAttributes: a).width))
        return d
    }()
    private static let sparkSlotW: [MenuBarMetric: CGFloat] = {
        let a = attrs
        return Dictionary(uniqueKeysWithValues: maxSparkLabel.map { metric, s in
            (metric, ceil((s as NSString).size(withAttributes: a).width))
        })
    }()

    init(engine: MetricsEngine, settings: SettingsStore) {
        self.engine = engine
        self.settings = settings
        super.init()
        createStatusItem()

        // Re-render on metric ticks (engine) AND on menu-bar config / appearance
        // changes (settings), debounced so a burst of @Published updates triggers
        // only one draw pass.
        engine.objectWillChange
            .merge(with: settings.objectWillChange)
            .merge(with: engine.alerts.objectWillChange)
            .debounce(for: .milliseconds(32), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                self?.render()
                self?.syncPopoverAppearance()
            }
            .store(in: &cancellables)

        render()
        registerShortcut()
    }

    deinit {
        if let m = localMonitor  { NSEvent.removeMonitor(m) }
        if let r = carbonHandlerRef { RemoveEventHandler(r) }
        if let h = hotKeyRef        { UnregisterEventHotKey(h) }
    }

    // MARK: - Global shortcut

    private func registerShortcut() {
        // Local monitor catches the shortcut when one of our own windows is focused.
        let flags = Self.shortcutFlags
        let code  = Self.shortcutKeyCode
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] e in
            if e.modifierFlags.intersection(.deviceIndependentFlagsMask) == flags, e.keyCode == code {
                self?.handleClick()
                return nil
            }
            return e
        }

        // Carbon RegisterEventHotKey fires system-wide without Accessibility permission,
        // unlike NSEvent.addGlobalMonitorForEvents which requires Input Monitoring entitlement.
        var eventSpec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let ctrl = Unmanaged<ExtraMenuBarController>.fromOpaque(userData).takeUnretainedValue()
            Task { @MainActor in ctrl.handleClick() }
            return noErr
        }, 1, &eventSpec, Unmanaged.passUnretained(self).toOpaque(), &carbonHandlerRef)

        let hotKeyID = EventHotKeyID(signature: 0x504D4150, id: 1)  // 'PMAP'
        RegisterEventHotKey(UInt32(kVK_ANSI_P), UInt32(cmdKey | optionKey), hotKeyID,
                            GetApplicationEventTarget(), 0, &hotKeyRef)
    }

    // MARK: - Status item

    private func createStatusItem() {
        guard engine != nil else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(handleClick)
        item.button?.sendAction(on: [.leftMouseDown])
        statusItem = item

        // Deliberately created *without* a contentViewController. See
        // `mountPopoverContent()` — the SwiftUI tree only exists while the
        // popover is actually on screen.
        let p = NSPopover()
        p.behavior = .transient
        p.delegate = self
        sharedPopover = p
    }

    // MARK: - Rendering

    private func render() {
        guard let engine else { return }
        let enabledMetrics = settings.menuBarOrder.filter { settings.isEnabled($0) }

        // The engine republishes every metric each tick even when the values a
        // menu-bar slot actually shows are unchanged (e.g. an idle network in
        // "Text only" stays "↓0 ↑0"). Hashing exactly the inputs the drawing
        // and the accessibility label depend on lets those ticks skip the whole
        // NSImage/CoreGraphics pass.
        let key = renderKey(for: enabledMetrics, engine: engine)
        guard key != lastRenderKey else { return }
        lastRenderKey = key

        let images = enabledMetrics.map { makeImage(for: $0, style: settings.styleFor($0), engine: engine) }
        statusItem?.button?.image = images.isEmpty ? nil : combinedImage(from: images)
        statusItem?.button?.setAccessibilityLabel(accessibilityLabel(for: enabledMetrics, engine: engine))
    }

    /// Hash of every value `makeImage` and `accessibilityLabel` read. Must be
    /// kept in step with those two methods — anything they consult belongs here.
    private func renderKey(for metrics: [MenuBarMetric], engine: MetricsEngine) -> Int {
        var hasher = Hasher()
        hasher.combine(settings.menuBarThresholdColor)
        hasher.combine(settings.diskDisplayMode)
        for metric in metrics {
            hasher.combine(metric)
            let effectiveStyle: MenuBarStyle =
                (metric == .disk && settings.diskDisplayMode == .space) ? .text : settings.styleFor(metric)
            hasher.combine(effectiveStyle)
            hasher.combine(engine.textOnlyLabel(for: metric))   // drawn and/or spoken
            if settings.menuBarThresholdColor {
                let status = engine.thresholdStatus(for: metric)
                hasher.combine(status.severity)
                hasher.combine(status.label)
            }
            if effectiveStyle == .sparkline {
                hasher.combine(engine.sparklineText(for: metric))
                for sample in engine.sparklineHistory(for: metric) { hasher.combine(sample) }
            }
        }
        return hasher.finalize()
    }

    // VoiceOver reads the icon-drawn image as nothing meaningful on its own, so the
    // status item needs an explicit label describing the actual current values —
    // e.g. "Performance Monitor: CPU 32%, Memory 61%". Rebuilt on every render pass
    // (already debounced), so it always reflects what's currently on screen.
    private func accessibilityLabel(for metrics: [MenuBarMetric], engine: MetricsEngine) -> String {
        guard !metrics.isEmpty else { return "Performance Monitor" }
        let parts = metrics.map { metric -> String in
            let base = engine.textOnlyLabel(for: metric)
            // Colour is never the only channel conveying threshold status —
            // fold it into the spoken label too, e.g. "CPU 92%, above alert threshold".
            guard settings.menuBarThresholdColor,
                  let suffix = engine.thresholdStatus(for: metric).label else { return base }
            return "\(base), \(suffix)"
        }
        return "Performance Monitor: " + parts.joined(separator: ", ")
    }

    // MARK: - Threshold colouring

    private func thresholdColor(for severity: ThresholdSeverity) -> NSColor {
        switch severity {
        case .normal:   return .white
        case .warning:  return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// Text attributes for a metric's slot. Reuses the shared, pre-measured
    /// `Self.attrs` whenever no colouring applies (the common case), so the
    /// fast path allocates nothing extra.
    private func textAttrs(for severity: ThresholdSeverity) -> [NSAttributedString.Key: Any] {
        guard settings.menuBarThresholdColor, severity != .normal else { return Self.attrs }
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: thresholdColor(for: severity)
        ]
    }

    private func makeImage(for metric: MenuBarMetric,
                           style: MenuBarStyle,
                           engine: MetricsEngine) -> NSImage {
        let h: CGFloat = 16
        let severity = settings.menuBarThresholdColor ? engine.thresholdStatus(for: metric).severity : .normal
        let attrs = textAttrs(for: severity)
        let sparkColor = thresholdColor(for: severity)

        // Disk in Space mode is always rendered as text — no sparkline applies.
        let effectiveStyle: MenuBarStyle =
            (metric == .disk && settings.diskDisplayMode == .space) ? .text : style

        switch effectiveStyle {
        case .text:
            let text   = engine.textOnlyLabel(for: metric)
            let fixedW = (metric == .disk && settings.diskDisplayMode == .space)
                ? Self.textSlotW[.disk]! // disk-space slot pre-measured from "DSK 16.0G"
                : Self.textSlotW[metric] ?? ceil((text as NSString).size(withAttributes: attrs).width)
            let sz     = (text as NSString).size(withAttributes: attrs)
            let textX  = fixedW - ceil(sz.width)
            let textY  = (h - sz.height) / 2
            return NSImage(size: NSSize(width: fixedW, height: h), flipped: false) { _ in
                guard NSGraphicsContext.current != nil else { return false }
                (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
                return true
            }

        case .sparkline:
            let text     = engine.sparklineText(for: metric)
            let sparkW   : CGFloat = 22
            let gap      : CGFloat = 2
            let maxTextW = Self.sparkSlotW[metric] ?? ceil((text as NSString).size(withAttributes: attrs).width)
            let totalW   = sparkW + gap + maxTextW
            let sz        = (text as NSString).size(withAttributes: attrs)
            let textX     = totalW - sz.width
            let textY     = (h - sz.height) / 2
            let history   = engine.sparklineHistory(for: metric)
            return NSImage(size: NSSize(width: totalW, height: h), flipped: false) { _ in
                guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
                if history.count > 1 {
                    let peak = max(history.max() ?? 1, 0.001)
                    let step = sparkW / CGFloat(history.count - 1)
                    func pt(_ i: Int) -> CGPoint {
                        CGPoint(x: CGFloat(i) * step, y: 1 + CGFloat(history[i] / peak) * (h - 3))
                    }
                    let path = CGMutablePath()
                    path.move(to: pt(0))
                    for i in 1..<history.count { path.addLine(to: pt(i)) }
                    ctx.addPath(path)
                    ctx.setStrokeColor(sparkColor.withAlphaComponent(0.85).cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.setLineCap(.round); ctx.setLineJoin(.round)
                    ctx.strokePath()
                    ctx.addPath(path)
                    ctx.addLine(to: CGPoint(x: CGFloat(history.count - 1) * step, y: 0))
                    ctx.addLine(to: CGPoint(x: 0, y: 0))
                    ctx.closePath()
                    ctx.setFillColor(sparkColor.withAlphaComponent(0.15).cgColor)
                    ctx.fillPath()
                }
                (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
                return true
            }
        }
    }

    private func combinedImage(from images: [NSImage]) -> NSImage {
        let gap: CGFloat = 2
        let h:   CGFloat = 16
        let totalW = images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(images.count - 1)
        return NSImage(size: NSSize(width: totalW, height: h), flipped: false) { _ in
            var x: CGFloat = 0
            for img in images {
                img.draw(in: NSRect(x: x, y: 0, width: img.size.width, height: h))
                x += img.size.width + gap
            }
            return true
        }
    }

    // MARK: - Click handling

    @objc private func handleClick() {
        guard let popover = sharedPopover, let button = statusItem?.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            mountPopoverContent()
            syncPopoverAppearance()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    // MARK: - Popover content lifecycle
    //
    // A popover that keeps its NSHostingController alive keeps the whole
    // OverviewView graph subscribed to the engine, so every metric tick
    // (~80 @Published writes per second) re-ran SwiftUI layout for a view
    // nobody was looking at — measurably the app's largest idle cost.
    // The view is therefore built on demand when the popover opens and torn
    // down again when it closes; opening is user-driven and rare, so paying
    // the construction cost there is far cheaper than paying layout forever.

    /// Builds the popover's SwiftUI content, laid out once up front so the
    /// popover opens at its final size showing the engine's current values —
    /// no empty first frame, no resize hitch.
    private func mountPopoverContent() {
        guard let engine,
              let popover = sharedPopover,
              popover.contentViewController == nil else { return }
        let host = NSHostingController(rootView: OverviewView(engine: engine))
        host.view.layoutSubtreeIfNeeded()
        popover.contentViewController = host
    }

    /// Releases the SwiftUI tree once the close animation has finished, so
    /// nothing observes the engine while the popover is hidden.
    func popoverDidClose(_ notification: Notification) {
        sharedPopover?.contentViewController = nil
    }

    private func syncPopoverAppearance() {
        // Only meaningful while the popover has content; assigning `appearance`
        // invalidates the hosted view tree's effective appearance, which would
        // itself force a SwiftUI layout pass on every tick.
        guard let popover = sharedPopover, popover.contentViewController != nil else { return }
        popover.appearance = switch settings.appAppearance {
        case .system: nil
        case .light:  NSAppearance(named: .aqua)
        case .dark:   NSAppearance(named: .darkAqua)
        }
    }
}

extension ExtraMenuBarController: NSPopoverDelegate {}
