import CoreGraphics
import Foundation
import ImageIO
import NivloDomain
import Testing
import UniformTypeIdentifiers

@testable import NivloImaging

@Suite("Core image geometry exporter")
struct CoreImageGeometryExporterTests {
  @Test("crops after rotation so landscape input becomes portrait output")
  func cropsAfterRotation() throws {
    let fixture = try GeometryExportFixture(width: 200, height: 100)
    let outputURL = fixture.rootURL.appending(path: "rotated-crop.png")
    let exporter = CoreImageGeometryExporter()

    try exporter.exportPNG(
      sourceURL: fixture.imageURL,
      outputURL: outputURL,
      cropRect: NormalizedCropRect(x: 0, y: 0, width: 1, height: 0.5),
      quarterTurns: 1
    )

    let dimensions = try imageDimensions(at: outputURL)
    #expect(dimensions.width == 100)
    #expect(dimensions.height == 100)
  }

  @Test("applies centered crop without rotation")
  func cropsWithoutRotation() throws {
    let fixture = try GeometryExportFixture(width: 120, height: 80)
    let outputURL = fixture.rootURL.appending(path: "crop.png")
    let exporter = CoreImageGeometryExporter()

    try exporter.exportPNG(
      sourceURL: fixture.imageURL,
      outputURL: outputURL,
      cropRect: NormalizedCropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5)
    )

    let dimensions = try imageDimensions(at: outputURL)
    #expect(dimensions.width == 60)
    #expect(dimensions.height == 40)
  }

  @Test("erase mask strokes remove previously painted mask regions")
  func eraseMaskStroke() throws {
    let fixture = try GeometryExportFixture(width: 100, height: 100)
    let outputURL = fixture.rootURL.appending(path: "erased-mask.png")
    let exporter = CoreImageGeometryExporter()

    try exporter.exportPNG(
      sourceURL: fixture.imageURL,
      outputURL: outputURL,
      maskStrokes: [
        MaskStroke(
          points: [
            MaskBrushPoint(x: 0.1, y: 0.5),
            MaskBrushPoint(x: 0.9, y: 0.5),
          ],
          brushRadius: 0.12,
          operation: .paint
        ),
        MaskStroke(
          points: [
            MaskBrushPoint(x: 0.45, y: 0.5),
            MaskBrushPoint(x: 0.55, y: 0.5),
          ],
          brushRadius: 0.08,
          operation: .erase
        ),
      ]
    )

    let paintedAlpha = try pixelAlpha(at: CGPoint(x: 20, y: 50), in: outputURL)
    let erasedAlpha = try pixelAlpha(at: CGPoint(x: 50, y: 50), in: outputURL)
    #expect(paintedAlpha > 0.9)
    #expect(erasedAlpha < 0.1, "Erased pixel alpha was \(erasedAlpha)")
  }

  @Test("annotations remain visible above a restrictive mask")
  func annotationsRenderAboveMask() throws {
    let fixture = try GeometryExportFixture(width: 100, height: 100)
    let outputURL = fixture.rootURL.appending(path: "annotation-above-mask.png")
    let exporter = CoreImageGeometryExporter()

    try exporter.exportPNG(
      sourceURL: fixture.imageURL,
      outputURL: outputURL,
      annotations: [
        ImageAnnotation(
          kind: .rectangle,
          normalizedRect: NormalizedCropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
          rectangleStyle: RectangleAnnotationStyle(
            strokeColor: .red,
            lineWidth: 8
          )
        )
      ],
      maskStrokes: [
        MaskStroke(
          points: [MaskBrushPoint(x: 0.5, y: 0.5)],
          brushRadius: 0.08
        )
      ]
    )

    let redBounds = try matchingPixelBounds(in: outputURL) { pixel in
      pixel.red > 0.7 && pixel.green < 0.45 && pixel.alpha > 0.7
    }
    #expect(redBounds != nil)
  }

  @Test("rotated rectangles render away from their unrotated corner")
  func rotatedRectangle() throws {
    let fixture = try GeometryExportFixture(width: 120, height: 120)
    let outputURL = fixture.rootURL.appending(path: "rotated-rectangle.png")
    let exporter = CoreImageGeometryExporter()

    try exporter.exportPNG(
      sourceURL: fixture.imageURL,
      outputURL: outputURL,
      annotations: [
        ImageAnnotation(
          kind: .rectangle,
          normalizedRect: NormalizedCropRect(x: 0.25, y: 0.4, width: 0.5, height: 0.2),
          rectangleStyle: RectangleAnnotationStyle(strokeColor: .red, lineWidth: 8),
          rotationDegrees: 90
        )
      ]
    )

    let redBounds = try matchingPixelBounds(in: outputURL) { pixel in
      pixel.red > 0.7 && pixel.green < 0.45 && pixel.alpha > 0.7
    }
    #expect(redBounds?.height ?? 0 > redBounds?.width ?? 0)
  }

  @Test("levels curves and color bands alter channel output")
  func advancedGlobalAdjustments() throws {
    let fixture = try GeometryExportFixture(width: 100, height: 100)
    let outputURL = fixture.rootURL.appending(path: "advanced-adjustments.png")
    let exporter = CoreImageGeometryExporter()
    var adjustments = ImageAdjustmentSettings(
      vibrance: 0.3,
      levels: [
        .rgb: ImageLevels(blackPoint: 0.05, whitePoint: 0.85, gamma: 1.2)
      ],
      curves: [
        .red: ToneCurve(points: [
          ToneCurvePoint(x: 0, y: 0),
          ToneCurvePoint(x: 0.2, y: 0.8),
          ToneCurvePoint(x: 1, y: 1),
        ])
      ],
      colorBands: [
        .blue: HSLBandAdjustment(hue: 0.1, saturation: 0.2, luminance: 0.1)
      ]
    )
    adjustments.tint = 0.1

    try exporter.exportPNG(
      sourceURL: fixture.imageURL,
      outputURL: outputURL,
      adjustments: adjustments
    )

    let source = try pixelRGBA(at: CGPoint(x: 50, y: 50), in: fixture.imageURL)
    let output = try pixelRGBA(at: CGPoint(x: 50, y: 50), in: outputURL)
    #expect(abs(source.red - output.red) > 0.1)
    #expect(abs(source.blue - output.blue) > 0.02)
  }

  @Test("local adjustment changes only its painted mask")
  func localAdjustmentMask() throws {
    let fixture = try GeometryExportFixture(width: 100, height: 100)
    let outputURL = fixture.rootURL.appending(path: "local-adjustment.png")
    let exporter = CoreImageGeometryExporter()

    try exporter.render(
      sourceURL: fixture.imageURL,
      outputURL: outputURL,
      snapshot: ImageEditSnapshot(
        localAdjustments: [
          LocalImageAdjustment(
            name: "Left",
            settings: ImageAdjustmentSettings(exposure: 1),
            maskStrokes: [
              MaskStroke(
                points: [
                  MaskBrushPoint(x: 0.1, y: 0.5),
                  MaskBrushPoint(x: 0.4, y: 0.5),
                ],
                brushRadius: 0.3
              )
            ]
          )
        ]
      )
    )

    let left = try pixelRGBA(at: CGPoint(x: 20, y: 50), in: outputURL)
    let right = try pixelRGBA(at: CGPoint(x: 85, y: 50), in: outputURL)
    #expect(left.red > right.red)
    #expect(left.green > right.green)
  }
}

private struct GeometryExportFixture {
  let rootURL: URL
  let imageURL: URL

  init(width: Int, height: Int) throws {
    rootURL = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    imageURL = rootURL.appending(path: "source.png")
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
    try writeFixtureImage(at: imageURL, width: width, height: height)
  }
}

private func writeFixtureImage(
  at url: URL,
  width: Int,
  height: Int
) throws {
  guard
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw GeometryExportFixtureError.creationFailed
  }
  context.setFillColor(CGColor(red: 0.2, green: 0.6, blue: 0.9, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else {
    throw GeometryExportFixtureError.creationFailed
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw GeometryExportFixtureError.creationFailed
  }
}

private func imageDimensions(at url: URL) throws -> (width: Int, height: Int) {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? Int,
    let height = properties[kCGImagePropertyPixelHeight] as? Int
  else {
    throw GeometryExportFixtureError.creationFailed
  }
  return (width, height)
}

private func pixelAlpha(at point: CGPoint, in url: URL) throws -> Double {
  try pixelRGBA(at: point, in: url).alpha
}

private func pixelRGBA(
  at point: CGPoint,
  in url: URL
) throws -> (red: Double, green: Double, blue: Double, alpha: Double) {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else {
    throw GeometryExportFixtureError.creationFailed
  }
  var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
  guard
    let context = CGContext(
      data: &pixels,
      width: image.width,
      height: image.height,
      bitsPerComponent: 8,
      bytesPerRow: image.width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw GeometryExportFixtureError.creationFailed
  }
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  let x = min(max(Int(point.x), 0), image.width - 1)
  let y = min(max(Int(point.y), 0), image.height - 1)
  let offset = (y * image.width + x) * 4
  return (
    Double(pixels[offset]) / 255,
    Double(pixels[offset + 1]) / 255,
    Double(pixels[offset + 2]) / 255,
    Double(pixels[offset + 3]) / 255
  )
}

private func matchingPixelBounds(
  in url: URL,
  predicate: ((red: Double, green: Double, blue: Double, alpha: Double)) -> Bool
) throws -> CGRect? {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
  else {
    throw GeometryExportFixtureError.creationFailed
  }
  var pixels = [UInt8](repeating: 0, count: image.width * image.height * 4)
  guard
    let context = CGContext(
      data: &pixels,
      width: image.width,
      height: image.height,
      bitsPerComponent: 8,
      bytesPerRow: image.width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw GeometryExportFixtureError.creationFailed
  }
  context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
  var minimumX = image.width
  var minimumY = image.height
  var maximumX = -1
  var maximumY = -1
  for y in 0..<image.height {
    for x in 0..<image.width {
      let offset = (y * image.width + x) * 4
      let pixel = (
        Double(pixels[offset]) / 255,
        Double(pixels[offset + 1]) / 255,
        Double(pixels[offset + 2]) / 255,
        Double(pixels[offset + 3]) / 255
      )
      guard predicate(pixel) else { continue }
      minimumX = min(minimumX, x)
      minimumY = min(minimumY, y)
      maximumX = max(maximumX, x)
      maximumY = max(maximumY, y)
    }
  }
  guard maximumX >= minimumX, maximumY >= minimumY else {
    return nil
  }
  return CGRect(
    x: minimumX,
    y: minimumY,
    width: maximumX - minimumX + 1,
    height: maximumY - minimumY + 1
  )
}

private enum GeometryExportFixtureError: Error {
  case creationFailed
}
