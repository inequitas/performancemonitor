import AppKit
import SwiftUI
import Combine

/// Owns the single NSStatusItem that shows all enabled metrics side-by-side.
/// Subscribes to the engine's raw metric publishers and renders images itself,
/// keeping all AppKit/CoreGraphics drawing out of MetricsEngine.
@MainActor
final class ExtraMenuBarController: NSObject {
    private weak var engine: MetricsEngine?
    private var statusItem: NSStatusItem?
    private var sharedPopover: NSPopover?
    private var cancellables: Set<AnyCancellable> = []

    // Fixed font/colour attributes — allocated once, shared across all renders.
    private static let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
        .foregroundColor: NSColor.white
    ]

    // Widest string each metric/style combo will ever produce, used to fix slot widths.
    private static let maxTextLabel: [MetricsEngine.MenuBarMetric: String] = [
        .cpu: "CPU 100%", .memory: "MEM 16.0G",
        .network: "↓9.9m ↑9.9m", .disk: "R 9999K W 9999K", .gpu: "GPU 100%"
    ]
    private static let maxTextLabelDiskSpace = "DSK 16.0G"
    private static let maxSparkLabel: [MetricsEngine.MenuBarMetric: String] = [
        .cpu: "100%", .memory: "16.0G", .network: "9.9m", .disk: "16.0G", .gpu: "100%"
    ]
    // Pre-measured widths so NSString.size() is never called at render time.
    private static let textSlotW: [MetricsEngine.MenuBarMetric: CGFloat] = {
        let a = attrs
        var d = Dictionary(uniqueKeysWithValues: maxTextLabel.map { metric, s in
            (metric, ceil((s as NSString).size(withAttributes: a).width))
        })
        d[.disk] = max(d[.disk] ?? 0, ceil((maxTextLabelDiskSpace as NSString).size(withAttributes: a).width))
        return d
    }()
    private static let sparkSlotW: [MetricsEngine.MenuBarMetric: CGFloat] = {
        let a = attrs
        return Dictionary(uniqueKeysWithValues: maxSparkLabel.map { metric, s in
            (metric, ceil((s as NSString).size(withAttributes: a).width))
        })
    }()

    init(engine: MetricsEngine) {
        self.engine = engine
        super.init()
        createStatusItem()

        // Re-render on metric/config changes, debounced so a single tick that updates
        // many @Published vars only triggers one draw pass.
        engine.objectWillChange
            .debounce(for: .milliseconds(32), scheduler: RunLoop.main)
            .sink { [weak self] _ in self?.render() }
            .store(in: &cancellables)

        render()
    }

    // MARK: - Status item

    private func createStatusItem() {
        guard let engine else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(handleClick)
        item.button?.sendAction(on: [.leftMouseDown])
        statusItem = item

        let p = NSPopover()
        p.contentViewController = NSHostingController(rootView: OverviewView(engine: engine))
        p.behavior = .transient
        sharedPopover = p
    }

    // MARK: - Rendering

    private func render() {
        guard let engine else { return }
        let images = engine.menuBarOrder
            .filter { engine.isEnabled($0) }
            .map { makeImage(for: $0, style: engine.styleFor($0), engine: engine) }
        statusItem?.button?.image = images.isEmpty ? nil : combinedImage(from: images)
    }

    private func makeImage(for metric: MetricsEngine.MenuBarMetric,
                           style: MetricsEngine.MenuBarStyle,
                           engine: MetricsEngine) -> NSImage {
        let h: CGFloat = 16
        let attrs = Self.attrs

        // Disk in Space mode is always rendered as text — no sparkline applies.
        let effectiveStyle: MetricsEngine.MenuBarStyle =
            (metric == .disk && engine.diskDisplayMode == .space) ? .text : style

        switch effectiveStyle {
        case .text:
            let text   = engine.textOnlyLabel(for: metric)
            let fixedW = (metric == .disk && engine.diskDisplayMode == .space)
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
                    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.85).cgColor)
                    ctx.setLineWidth(1.5)
                    ctx.setLineCap(.round); ctx.setLineJoin(.round)
                    ctx.strokePath()
                    ctx.addPath(path)
                    ctx.addLine(to: CGPoint(x: CGFloat(history.count - 1) * step, y: 0))
                    ctx.addLine(to: CGPoint(x: 0, y: 0))
                    ctx.closePath()
                    ctx.setFillColor(NSColor.white.withAlphaComponent(0.15).cgColor)
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
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
