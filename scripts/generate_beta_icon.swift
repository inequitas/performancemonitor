// Draws a "BETA" ribbon badge onto the existing app icon master image, for
// use by the --beta build (see build_app.sh / scripts/build_beta_icon.sh).
//
// Usage: swift scripts/generate_beta_icon.swift <input.png> <output.png>

import AppKit
import CoreGraphics

guard CommandLine.arguments.count >= 3 else {
    fatalError("Usage: generate_beta_icon.swift <input.png> <output.png>")
}

let inputURL  = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let baseImage = NSImage(contentsOfFile: inputURL.path) else {
    fatalError("Could not load \(inputURL.path)")
}

// Use the image's actual pixel size (not its "points" size) so the badge
// stays crisp on the high-resolution master.
guard let baseRep = baseImage.representations.first else {
    fatalError("Source image has no representation")
}
let pixelSize = CGSize(width: baseRep.pixelsWide, height: baseRep.pixelsHigh)

let image = NSImage(size: pixelSize)
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

baseImage.draw(in: CGRect(origin: .zero, size: pixelSize),
                from: .zero, operation: .copy, fraction: 1.0)

// Diagonal ribbon across the bottom-right corner reading "BETA", in the same
// spirit as Xcode/TestFlight beta badges.
let ribbonColor = CGColor(red: 0.96, green: 0.34, blue: 0.13, alpha: 1.0) // orange-red
let ribbonThickness = pixelSize.height * 0.16

ctx.saveGState()
ctx.translateBy(x: pixelSize.width * 0.5, y: pixelSize.height * 0.18)
ctx.rotate(by: -.pi / 4)

let bandLength = pixelSize.width * 1.6
let bandRect = CGRect(x: -bandLength / 2, y: -ribbonThickness / 2,
                       width: bandLength, height: ribbonThickness)
ctx.setFillColor(ribbonColor)
ctx.fill(bandRect)
// Thin darker edge lines so the ribbon reads clearly against any background.
ctx.setFillColor(CGColor(red: 0.62, green: 0.18, blue: 0.04, alpha: 1.0))
ctx.fill(CGRect(x: -bandLength / 2, y: ribbonThickness / 2 - ribbonThickness * 0.06,
                 width: bandLength, height: ribbonThickness * 0.06))
ctx.fill(CGRect(x: -bandLength / 2, y: -ribbonThickness / 2,
                 width: bandLength, height: ribbonThickness * 0.06))

let text = "BETA"
let font = NSFont.systemFont(ofSize: ribbonThickness * 0.56, weight: .heavy)
let paragraph = NSMutableParagraphStyle()
paragraph.alignment = .center
let attrs: [NSAttributedString.Key: Any] = [
    .font: font,
    .foregroundColor: NSColor.white,
    .kern: ribbonThickness * 0.06,
    .paragraphStyle: paragraph
]
let attrString = NSAttributedString(string: text, attributes: attrs)
let textSize = attrString.size()

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: false)
attrString.draw(at: CGPoint(x: -textSize.width / 2, y: -textSize.height / 2))
NSGraphicsContext.restoreGraphicsState()

ctx.restoreGState()
image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let bitmap = NSBitmapImageRep(data: tiff),
      let pngData = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}

try pngData.write(to: outputURL)
print("Wrote \(outputURL.path)")
