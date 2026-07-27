import AppKit
import SwiftUI
import Combine
import Carbon
import PerformanceAppCore

/// Owns the NSStatusItem(s) that show all enabled metrics: either one item
/// per metric, or (when "Combine into one menu bar item" is on) a single item
/// with every metric's image side-by-side. Subscribes to the engine's raw
/// metric publishers and renders images itself, keeping all AppKit/CoreGraphics
/// drawing out of MetricsEngine.
@MainActor
final class ExtraMenuBarController: NSObject {
    private weak var engine: MetricsEngine?
    private let settings: SettingsStore
    // Exactly one of these two is populated at any time, depending on
    // `settings.combineMenuBarItems`: either a single item holding every
    // enabled metric's image side-by-side, or one item per enabled metric
    // (in `menuBarOrder`) so menu-bar managers like Bartender/Ice can hide or
    // reposition metrics individually.
    private var combinedStatusItem: NSStatusItem?
    private var perMetricStatusItems: [MenuBarMetric: NSStatusItem] = [:]
    /// The ordered, enabled-metric list the separate-item set was last built
    /// for. Rebuilt (torn down + recreated) only when this changes, so a
    /// plain value tick never touches NSStatusBar.
    private var lastSeparateOrder: [MenuBarMetric] = []
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

    init(engine: MetricsEngine, settings: SettingsStore) {
        self.engine = engine
        self.settings = settings
        super.init()
        createPopover()

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

    /// Deliberately created *without* a contentViewController. See
    /// `mountPopoverContent()` — the SwiftUI tree only exists while the
    /// popover is actually on screen.
    private func createPopover() {
        let p = NSPopover()
        p.behavior = .transient
        p.delegate = self
        sharedPopover = p
    }

    private func makeStatusItem() -> NSStatusItem {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(handleClick(_:))
        item.button?.sendAction(on: [.leftMouseDown])
        return item
    }

    private func teardownCombinedItem() {
        guard let item = combinedStatusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        combinedStatusItem = nil
    }

    private func teardownSeparateItems() {
        for item in perMetricStatusItems.values { NSStatusBar.system.removeStatusItem(item) }
        perMetricStatusItems.removeAll()
        lastSeparateOrder = []
    }

    // MARK: - Rendering

    private func render() {
        guard let engine else { return }
        let enabledMetrics = settings.menuBarOrder.filter { settings.isEnabled($0) }
        if settings.combineMenuBarItems {
            renderCombined(enabledMetrics: enabledMetrics, engine: engine)
        } else {
            renderSeparate(enabledMetrics: enabledMetrics, engine: engine)
        }
    }

    /// One NSStatusItem holding every enabled metric's image side-by-side,
    /// separated by a thin vertical divider.
    private func renderCombined(enabledMetrics: [MenuBarMetric], engine: MetricsEngine) {
        teardownSeparateItems()
        if combinedStatusItem == nil { combinedStatusItem = makeStatusItem() }

        // The engine republishes every metric each tick even when the values a
        // menu-bar slot actually shows are unchanged (e.g. an idle network in
        // "Text only" stays "↓0 ↑0"). Hashing exactly the inputs the drawing
        // and the accessibility label depend on lets those ticks skip the whole
        // NSImage/CoreGraphics pass.
        let key = renderKey(for: enabledMetrics, engine: engine)
        guard key != lastRenderKey else { return }
        lastRenderKey = key

        // Draw list-reversed so the combined item matches the visual order of
        // the separate items: NSStatusItems insert right-to-left, so the topmost
        // metric in `menuBarOrder` ends up rightmost. `combinedImage` draws
        // left-to-right, so the leftmost drawn metric must be the LAST in the
        // list — keeping both modes in the same on-screen order.
        let images = enabledMetrics.reversed().map { makeImage(for: $0, style: settings.styleFor($0), engine: engine) }
        combinedStatusItem?.button?.image = images.isEmpty ? nil : MenuBarRenderer.combinedImage(from: images)
        combinedStatusItem?.button?.setAccessibilityLabel(accessibilityLabel(for: enabledMetrics, engine: engine))
    }

    /// One NSStatusItem per enabled metric, in `menuBarOrder`, so a menu-bar
    /// manager can hide/reposition each metric independently.
    private func renderSeparate(enabledMetrics: [MenuBarMetric], engine: MetricsEngine) {
        teardownCombinedItem()

        // Status items can't be reordered in place, so any change to *which*
        // metrics are enabled or *what order* they're in tears the whole set
        // down and recreates it fresh, in the right order. A plain value tick
        // (the common case) leaves the existing items untouched.
        if enabledMetrics != lastSeparateOrder {
            teardownSeparateItems()
            for metric in enabledMetrics {
                perMetricStatusItems[metric] = makeStatusItem()
            }
            lastSeparateOrder = enabledMetrics
        }

        let key = renderKey(for: enabledMetrics, engine: engine)
        guard key != lastRenderKey else { return }
        lastRenderKey = key

        for metric in enabledMetrics {
            guard let item = perMetricStatusItems[metric] else { continue }
            item.button?.image = makeImage(for: metric, style: settings.styleFor(metric), engine: engine)
            item.button?.setAccessibilityLabel(accessibilityLabel(for: [metric], engine: engine))
        }
    }

    /// Hash of every value `makeImage` and `accessibilityLabel` read. Must be
    /// kept in step with those two methods — anything they consult belongs here.
    private func renderKey(for metrics: [MenuBarMetric], engine: MetricsEngine) -> Int {
        var hasher = Hasher()
        // Included so a toggle of combine/separate mode is never mistaken for
        // a no-op tick — the freshly (re)created status item(s) always get an
        // explicit image/label set at least once after a mode switch.
        hasher.combine(settings.combineMenuBarItems)
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

    // MARK: - Rendering (delegates to MenuBarRenderer)

    /// Resolves the current engine/settings values for `metric` and hands them
    /// to the shared `MenuBarRenderer` — the same code path the onboarding
    /// tour's live preview uses, so both stay pixel-identical.
    private func makeImage(for metric: MenuBarMetric,
                           style: MenuBarStyle,
                           engine: MetricsEngine) -> NSImage {
        let severity = settings.menuBarThresholdColor ? engine.thresholdStatus(for: metric).severity : .normal
        // Disk in Space mode is always rendered as text — no sparkline applies.
        let isDiskSpace = (metric == .disk && settings.diskDisplayMode == .space)
        let effectiveStyle: MenuBarStyle = isDiskSpace ? .text : style
        return MenuBarRenderer.image(
            metric: metric,
            effectiveStyle: effectiveStyle,
            text: engine.textOnlyLabel(for: metric),
            sparkText: engine.sparklineText(for: metric),
            history: engine.sparklineHistory(for: metric),
            severity: severity,
            isDiskSpace: isDiskSpace
        )
    }

    // MARK: - Click handling

    /// `sender` is the status item button that was actually clicked — in
    /// separate-items mode any one of them can trigger this. The keyboard
    /// shortcut has no sender, so it falls back to whichever button currently
    /// exists (combined item, or the first separate item).
    @objc private func handleClick(_ sender: NSStatusBarButton? = nil) {
        guard let popover = sharedPopover else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            showPopover(from: sender)
        }
    }

    /// The status-item button to anchor the popover to. `preferred` is the
    /// button that was actually clicked (any one of the separate items can
    /// trigger a click); everything else falls back to the combined item, then
    /// the first separate item in menu-bar order.
    private func anchorButton(preferred: NSStatusBarButton? = nil) -> NSStatusBarButton? {
        preferred ?? combinedStatusItem?.button
            ?? settings.menuBarOrder.compactMap { perMetricStatusItems[$0]?.button }.first
    }

    /// Shows the shared popover anchored to a menu-bar status item. Shared by
    /// real clicks (`handleClick`) and the onboarding tour's "Open the overview"
    /// step, so both anchor to the icon in exactly the same way.
    private func showPopover(from preferred: NSStatusBarButton? = nil) {
        guard let popover = sharedPopover, let button = anchorButton(preferred: preferred) else { return }
        mountPopoverContent()
        syncPopoverAppearance()
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the shared popover from outside a status-item click — used by the
    /// onboarding tour's "Open the overview" step so it shows the real popover,
    /// anchored to the menu-bar icon. Shows it directly relative to the status
    /// item rather than going through the button's `performClick`, whose action
    /// is gated to `.leftMouseDown` and so isn't reliably delivered by a
    /// synthetic click — that left the popover unanchored, opening in the wrong
    /// corner. No-op if already shown. Returns `false` when there is no status
    /// item to anchor to (e.g. no menu-bar metric enabled), so the caller can
    /// show a fallback hint instead.
    @discardableResult
    func openPopover() -> Bool {
        guard let popover = sharedPopover, anchorButton() != nil else { return false }
        if !popover.isShown { showPopover() }
        return true
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
