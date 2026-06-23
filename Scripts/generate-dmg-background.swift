import AppKit
import Foundation

guard CommandLine.arguments.count == 2 else {
  fputs("usage: generate-dmg-background.swift <output.png>\n", stderr)
  exit(1)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let width = 660
let height = 400

guard
  let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: width,
    pixelsHigh: height,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  fputs("failed to allocate background bitmap\n", stderr)
  exit(1)
}

NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)

let gradient = NSGradient(
  colors: [
    NSColor(calibratedRed: 0.05, green: 0.08, blue: 0.15, alpha: 1),
    NSColor(calibratedRed: 0.09, green: 0.13, blue: 0.22, alpha: 1),
  ]
)
gradient?.draw(in: NSRect(x: 0, y: 0, width: width, height: height), angle: 90)

let arrowPath = NSBezierPath()
arrowPath.move(to: NSPoint(x: 300, y: 210))
arrowPath.line(to: NSPoint(x: 360, y: 210))
arrowPath.line(to: NSPoint(x: 350, y: 220))
arrowPath.move(to: NSPoint(x: 360, y: 210))
arrowPath.line(to: NSPoint(x: 350, y: 200))
NSColor(calibratedWhite: 1, alpha: 0.22).setStroke()
arrowPath.lineWidth = 3
arrowPath.stroke()

let title = "Drag Nivlo to Applications"
let subtitle = "将 Nivlo 拖到“应用程序”文件夹"
let titleAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 20, weight: .semibold),
  .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.9),
]
let subtitleAttributes: [NSAttributedString.Key: Any] = [
  .font: NSFont.systemFont(ofSize: 13, weight: .regular),
  .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.55),
]

let titleSize = (title as NSString).size(withAttributes: titleAttributes)
(title as NSString).draw(
  at: NSPoint(x: (CGFloat(width) - titleSize.width) / 2, y: 72),
  withAttributes: titleAttributes
)

let subtitleSize = (subtitle as NSString).size(withAttributes: subtitleAttributes)
(subtitle as NSString).draw(
  at: NSPoint(x: (CGFloat(width) - subtitleSize.width) / 2, y: 48),
  withAttributes: subtitleAttributes
)

NSGraphicsContext.restoreGraphicsState()

guard let png = bitmap.representation(using: .png, properties: [:]) else {
  fputs("failed to encode dmg background\n", stderr)
  exit(1)
}

do {
  try png.write(to: outputURL)
} catch {
  fputs("failed to write dmg background: \(error)\n", stderr)
  exit(1)
}
