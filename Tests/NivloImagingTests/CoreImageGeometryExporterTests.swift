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

private enum GeometryExportFixtureError: Error {
  case creationFailed
}
