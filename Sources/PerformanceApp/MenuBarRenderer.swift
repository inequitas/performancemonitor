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
    /// How a normal-severity (uncoloured) slot is tinted.
    ///
    /// The menu bar's background follows the system theme, so any fixed pixel
    /// colour is unreadable in one of the two appearances (white text on a
    /// light bar). The fix is the same one system status items use: draw black
    /// and mark the image template, and macOS retints it per menu-bar
    /// appearance — black on a light bar, white on a dark one — with no redraw
    /// needed when the theme flips.
    ///
    /// - template: black pixels + `isTemplate = true`. The normal path for
    ///   real status items.
    /// - white: literal white, non-template. The onboarding preview draws on
    ///   a dark mock menu bar and wants exactly the shipped look.
    /// - dynamic: `labelColor`, resolved against the real menu-bar appearance
    ///   at draw time. For a combined item whose sibling metric is currently
    ///   alert-coloured: the whole image must stay non-template, so normal
    ///   slots pick their colour from the bar's appearance instead.
    enum Tint {
        case template
        case white
        case dynamic
    }

    static func normalColor(for tint: Tint) -> NSColor {
        switch tint {
        case .template: .black
        case .white:    .white
        case .dynamic:  .labelColor
        }
    }

    /// Fixed font attributes — allocated once, shared across all renders.
    /// Colour is deliberately not part of this dictionary: slot widths depend
    /// only on the font, while the colour varies by `Tint` and severity.
    static let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium)
    ]

    /// Pre-built text attributes per tint for the (common) uncoloured path, so
    /// a fast-path render allocates nothing extra.
    private static let normalAttrs: [Tint: [NSAttributedString.Key: Any]] = [
        .template: [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.black],
        .white:    [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.white],
        .dynamic:  [.font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium), .foregroundColor: NSColor.labelColor]
    ]

    // Widest string each metric/style combo will ever produce, used to fix slot widths.
    private static let maxTextLabel: [MenuBarMetric: String] = [
        .cpu: "CPU 100%", .memory: "MEM 16.0G",
        .network: "↓9.9m ↑9.9m", .disk: "R 9999K W 9999K", .gpu: "GPU 100%",
        .power: "PWR 199W"
    ]
    private static let maxTextLabelDiskSpace = "DSK 16.0G"
    private static let maxSparkLabel: [MenuBarMetric: String] = [
        .cpu: "100%", .memory: "16.0G", .network: "9.9m", .disk: "16.0G", .gpu: "100%",
        .power: "199W"
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

    /// Alert colours for a metric slot. Normal severity never reaches here in
    /// practice — it is tinted through `Tint` so it adapts to the menu-bar
    /// appearance — but the case is kept total for safety.
    static func thresholdColor(for severity: ThresholdSeverity) -> NSColor {
        switch severity {
        case .normal:   return .black
        case .warning:  return .systemOrange
        case .critical: return .systemRed
        }
    }

    /// Text attributes for a metric's slot. Reuses the pre-built normal-path
    /// dictionary whenever no alert colouring applies (the common case), so
    /// the fast path allocates nothing extra. Callers pass `.normal` when
    /// threshold colouring is disabled, so gating on severity alone suffices.
    private static func textAttrs(for severity: ThresholdSeverity, tint: Tint) -> [NSAttributedString.Key: Any] {
        guard severity != .normal else { return normalAttrs[tint]! }
        return [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: thresholdColor(for: severity)
        ]
    }

    /// Draws a single metric's menu-bar image. All values are pre-resolved by
    /// the caller so this stays pure. `text` is used in `.text` mode,
    /// `sparkText` + `history` in `.sparkline` mode. `isDiskSpace` selects the
    /// wider disk-space slot width and is only meaningful for `.disk`/`.text`.
    /// `tint` decides how a normal-severity slot gets its colour (see `Tint`);
    /// `appearance`, when given, is made current during drawing so dynamic
    /// colours (`.dynamic` tint, alert variants) resolve against the real
    /// menu-bar look rather than the app's.
    static func image(metric: MenuBarMetric,
                      effectiveStyle: MenuBarStyle,
                      text: String,
                      sparkText: String,
                      history: [Double],
                      severity: ThresholdSeverity,
                      isDiskSpace: Bool,
                      tint: Tint = .template,
                      appearance: NSAppearance? = nil) -> NSImage {
        let previous = NSAppearance.current
        if let appearance { NSAppearance.current = appearance }
        defer { NSAppearance.current = previous }

        let img = drawMetric(metric: metric,
                             effectiveStyle: effectiveStyle,
                             text: text,
                             sparkText: sparkText,
                             history: history,
                             severity: severity,
                             isDiskSpace: isDiskSpace,
                             tint: tint)
        // Template only for uncoloured drawings: an alert-coloured slot must
        // keep its orange/red, so it ships as a regular (non-retinted) image.
        img.isTemplate = (tint == .template && severity == .normal)
        return img
    }

    private static func drawMetric(metric: MenuBarMetric,
                                   effectiveStyle: MenuBarStyle,
                                   text: String,
                                   sparkText: String,
                                   history: [Double],
                                   severity: ThresholdSeverity,
                                   isDiskSpace: Bool,
                                   tint: Tint) -> NSImage {
        let h: CGFloat = 16
        let attrs = textAttrs(for: severity, tint: tint)
        let sparkColor = severity == .normal ? normalColor(for: tint) : thresholdColor(for: severity)

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
    ///
    /// The result is template only when every component is template (no alert
    /// colouring anywhere), so macOS retints the whole strip — divider
    /// included — on theme flips. With any alert colour in the mix the image
    /// stays non-template; the divider then uses dynamic `labelColor`, which
    /// callers resolve against the menu-bar appearance via `appearance`.
    static func combinedImage(from images: [NSImage], appearance: NSAppearance? = nil) -> NSImage {
        let gap: CGFloat = 6
        let h:   CGFloat = 16
        let totalW = images.reduce(0) { $0 + $1.size.width } + gap * CGFloat(images.count - 1)
        let previous = NSAppearance.current
        if let appearance { NSAppearance.current = appearance }
        defer { NSAppearance.current = previous }

        let img = NSImage(size: NSSize(width: totalW, height: h), flipped: false) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            var x: CGFloat = 0
            for (i, img) in images.enumerated() {
                if i > 0 {
                    let dividerX = x - gap / 2
                    // Colour is irrelevant on the template path (macOS retints
                    // the whole image); on the non-template path labelColor
                    // resolves to a divider visible on either bar appearance.
                    ctx.setStrokeColor(NSColor.labelColor.withAlphaComponent(0.35).cgColor)
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
        img.isTemplate = !images.isEmpty && images.allSatisfy(\.isTemplate)
        return img
    }
}
