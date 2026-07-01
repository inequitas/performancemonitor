import AppKit
import CoreGraphics

let size: CGFloat = 1024
let rect = CGRect(x: 0, y: 0, width: size, height: size)

let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// Background: dark rounded squircle
let cornerRadius = size * 0.225
let bgPath = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
ctx.addPath(bgPath)
ctx.clip()
ctx.setFillColor(CGColor(red: 0.10, green: 0.10, blue: 0.12, alpha: 1.0))
ctx.fill(rect)
ctx.resetClip()

// Four signal bars of increasing height, centered
// Symbis brand palette: dark forest green → olive → bright yellow
let barColors: [CGColor] = [
    CGColor(red: 0.118, green: 0.157, blue: 0.024, alpha: 1.0),  // darkGreen  #1E2806
    CGColor(red: 0.220, green: 0.290, blue: 0.040, alpha: 1.0),  // mid green  #384A0A
    CGColor(red: 0.557, green: 0.616, blue: 0.071, alpha: 1.0),  // olive      #8E9D12
    CGColor(red: 0.988, green: 0.910, blue: 0.184, alpha: 1.0),  // yellow     #FCE82F
]

let barCount = 4
let barWidth: CGFloat = size * 0.12
let barGap: CGFloat = size * 0.055
let maxBarHeight: CGFloat = size * 0.60
let minBarHeight: CGFloat = size * 0.18
let barCorner: CGFloat = barWidth * 0.35

let totalWidth = CGFloat(barCount) * barWidth + CGFloat(barCount - 1) * barGap
let startX = (size - totalWidth) / 2
let baseY: CGFloat = size * 0.20   // bottom of bars

for i in 0..<barCount {
    let fraction = CGFloat(i + 1) / CGFloat(barCount)
    let barHeight = minBarHeight + (maxBarHeight - minBarHeight) * fraction
    let x = startX + CGFloat(i) * (barWidth + barGap)
    let y = baseY

    let barRect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
    let barPath = CGPath(roundedRect: barRect, cornerWidth: barCorner, cornerHeight: barCorner, transform: nil)

    ctx.setFillColor(barColors[i])
    ctx.addPath(barPath)
    ctx.fillPath()
}

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
try pngData.write(to: outputURL)
print("Wrote \(outputURL.path)")
