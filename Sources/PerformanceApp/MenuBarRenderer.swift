import AppKit
import PerformanceAppCore

/// Pure menu-bar drawing code, shared by the live `ExtraMenuBarController`
/// (what actually appears next to the clock) and the onboarding tour's live
/// preview (`MenuBarPreview`). Keeping the CoreGraphics/NSImage drawing here —
/// with every input passed in explicitly rather than read from the engine —
/// guarantees the preview is pixel-for-pixel identical to the real menu bar,
/// and there is exactly one place to change if the drawing ever changes.
@MainActor
enum MenuBarRenderer {
    /// Fixed font/colour attributes — allocated once, shared across all renders.
    static let attrs: [NSAttributedString.Key: Any] = [
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

    /// Pre-measured widths so NSString.size() is never called at render time.
    static let textSlotW: [MenuBarMetric: CGFloat] = {
        let a = attrs
        var d = Dictionary(uniqueKeysWithValues: maxTextLabel.map { metric, s in
            (metric, ceil((s as NSString).size(withAttributes: a).width))
        })
        d[.disk] = max(d[.disk] ?? 0, ceil((maxTextLabelDiskSpace as NSString).size(withAttributes: a).width))
        return d
    }()
    static let sparkSlotW: [MenuBarMetric: CGFloat] = {
        let a = attrs
        return Dictionary(uniqueKeysWithValues: maxSparkLabel.map { metric, s in
            (metric, ceil((s as NSString).size(withAttributes: a).width))
        })
    }()

    static func thresholdColor(for severity: ThresholdSeverity) -> NSColor {
        switch severity {
        case .normal:   return .white
        case .warning:  return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// Text attributes for a metric's slot. Reuses the shared, pre-measured
    /// `attrs` whenever no colouring applies (the common case), so the fast
    /// path allocates nothing extra. Callers pass `.normal` when threshold
    /// colouring is disabled, so gating on severity alone is sufficient.
    private static func textAttrs(for severity: ThresholdSeverity) -> [NSAttributedString.Key: Any] {
        guard severity != .normal else { return attrs }
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: thresholdColor(for: severity)
        ]
    }

    /// Draws a single metric's menu-bar image. All values are pre-resolved by
    /// the caller so this stays pure. `text` is used in `.text` mode,
    /// `sparkText` + `history` in `.sparkline` mode. `isDiskSpace` selects the
    /// wider disk-space slot width and is only meaningful for `.disk`/`.text`.
    static func image(metric: MenuBarMetric,
                      effectiveStyle: MenuBarStyle,
                      text: String,
                      sparkText: String,
                      history: [Double],
                      severity: ThresholdSeverity,
                      isDiskSpace: Bool) -> NSImage {
        let h: CGFloat = 16
        let attrs = textAttrs(for: severity)
        let sparkColor = thresholdColor(for: severity)

        switch effectiveStyle {
        case .text:
            let fixedW = isDiskSpace
                ? textSlotW[.disk]! // disk-space slot pre-measured from "DSK 16.0G"
                : textSlotW[metric] ?? ceil((text as NSString).size(withAttributes: attrs).width)
            let sz     = (text as NSString).size(withAttributes: attrs)
            let textX  = fixedW - ceil(sz.width)
            let textY  = (h - sz.height) / 2
            return NSImage(size: NSSize(width: fixedW, height: h), flipped: false) { _ in
                guard NSGraphicsContext.current != nil else { return false }
                (text as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
                return true
            }

        case .sparkline:
            let sparkW   : CGFloat = 22
            let gap      : CGFloat = 2
            let maxTextW = sparkSlotW[metric] ?? ceil((sparkText as NSString).size(withAttributes: attrs).width)
            let totalW   = sparkW + gap + maxTextW
            let sz        = (sparkText as NSString).size(withAttributes: attrs)
            let textX     = totalW - sz.width
            let textY     = (h - sz.height) / 2
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
                (sparkText as NSString).draw(at: NSPoint(x: textX, y: textY), withAttributes: attrs)
                return true
            }
        }
    }

    /// Combines several already-rendered per-metric images into one, for
    /// "Combine into one menu bar item" mode. A subtle 1pt divider marks the
    /// boundary between metrics (skipped for single-metric configurations).
    static func combinedImage(from images: [NSImage]) -> NSImage {
        let gap: CGFloat = 6
        let h:   CGFloat = 16
        let totalW = images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(images.count - 1)
        return NSImage(size: NSSize(width: totalW, height: h), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var x: CGFloat = 0
            for (i, img) in images.enumerated() {
                if i > 0 {
                    let dividerX = x - gap / 2
                    ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.35).cgColor)
                    ctx.setLineWidth(1)
                    ctx.move(to: CGPoint(x: dividerX, y: 2))
                    ctx.addLine(to: CGPoint(x: dividerX, y: h - 2))
                    ctx.strokePath()
                }
                img.draw(in: NSRect(x: x, y: 0, width: img.size.width, height: h))
                x += img.size.width + gap
            }
            return true
        }
    }
}
