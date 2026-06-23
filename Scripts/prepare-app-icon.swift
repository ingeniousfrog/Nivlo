import AppKit
import Foundation

guard CommandLine.arguments.count == 3 else {
  fputs("usage: prepare-app-icon.swift <input.png> <output.png>\n", stderr)
  exit(1)
}

let inputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

guard let source = NSImage(contentsOf: inputURL),
  let sourceTIFF = source.tiffRepresentation,
  let sourceBitmap = NSBitmapImageRep(data: sourceTIFF)
else {
  fputs("failed to load input icon\n", stderr)
  exit(1)
}

let targetSize = 1024
let cropOriginX = max(0, (sourceBitmap.pixelsWide - targetSize) / 2)
let cropOriginY = max(0, (sourceBitmap.pixelsHigh - targetSize) / 2)
let cropWidth = min(targetSize, sourceBitmap.pixelsWide)
let cropHeight = min(targetSize, sourceBitmap.pixelsHigh)

guard let cgImage = sourceBitmap.cgImage else {
  fputs("failed to read source cgImage\n", stderr)
  exit(1)
}

let cropRect = CGRect(
  x: cropOriginX,
  y: cropOriginY,
  width: cropWidth,
  height: cropHeight
)
guard let croppedCG = cgImage.cropping(to: cropRect) else {
  fputs("failed to crop icon\n", stderr)
  exit(1)
}
let cropped = NSBitmapImageRep(cgImage: croppedCG)

if let croppedData = cropped.bitmapData {
  let pixelCount = cropWidth * cropHeight
  for index in 0..<pixelCount {
    let offset = index * 4
    let red = Int(croppedData[offset])
    let green = Int(croppedData[offset + 1])
    let blue = Int(croppedData[offset + 2])
    if red < 40 && green < 40 && blue < 40 {
      croppedData[offset] = 10
      croppedData[offset + 1] = 18
      croppedData[offset + 2] = 36
      croppedData[offset + 3] = 255
    }
  }
}

guard
  let canvas = NSBitmapImageRep(
    bitmapDataPlanes: nil,
    pixelsWide: targetSize,
    pixelsHigh: targetSize,
    bitsPerSample: 8,
    samplesPerPixel: 4,
    hasAlpha: true,
    isPlanar: false,
    colorSpaceName: .deviceRGB,
    bytesPerRow: 0,
    bitsPerPixel: 0
  )
else {
  fputs("failed to allocate output bitmap\n", stderr)
  exit(1)
}

let background = NSColor(calibratedRed: 0.04, green: 0.07, blue: 0.14, alpha: 1)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: canvas)
background.setFill()
NSRect(x: 0, y: 0, width: targetSize, height: targetSize).fill()

let drawRect = NSRect(
  x: CGFloat((targetSize - cropWidth) / 2),
  y: CGFloat((targetSize - cropHeight) / 2),
  width: CGFloat(cropWidth),
  height: CGFloat(cropHeight)
)
NSImage(size: drawRect.size, flipped: false) { _ in
  NSGraphicsContext.current?.cgContext.interpolationQuality = .high
  cropped.draw(in: NSRect(origin: .zero, size: drawRect.size))
  return true
}.draw(in: drawRect)

NSGraphicsContext.restoreGraphicsState()

guard let png = canvas.representation(using: .png, properties: [:]) else {
  fputs("failed to encode png\n", stderr)
  exit(1)
}

do {
  try png.write(to: outputURL)
} catch {
  fputs("failed to write output icon: \(error)\n", stderr)
  exit(1)
}
