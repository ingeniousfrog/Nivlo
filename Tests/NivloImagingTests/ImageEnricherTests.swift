import CryptoKit
import Foundation
import ImageIO
import NivloDomain
import Testing
import UniformTypeIdentifiers

@testable import NivloImaging

@Suite("Image enrichment")
struct ImageEnricherTests {
  @Test("computes the exact SHA-256 of the original file bytes")
  func computesExactHash() async throws {
    let fixture = try ImagingFixture()
    let sourceData = try Data(contentsOf: fixture.imageURL)
    let expected = SHA256.hash(data: sourceData)
      .map { String(format: "%02x", $0) }
      .joined()
    let enricher = ImageEnricher(cacheDirectory: fixture.cacheURL)

    let enrichment = try await enricher.enrich(fixture.asset)

    #expect(enrichment.exactHash == expected)
  }

  @Test("computes a stable 64-bit perceptual hash")
  func computesPerceptualHash() async throws {
    let fixture = try ImagingFixture()
    let enricher = ImageEnricher(cacheDirectory: fixture.cacheURL)

    let first = try await enricher.enrich(fixture.asset)
    let second = try await enricher.enrich(fixture.asset)

    #expect(first.perceptualHash == second.perceptualHash)
  }

  @Test("extracts TIFF camera metadata")
  func extractsMetadata() async throws {
    let fixture = try ImagingFixture()
    let enricher = ImageEnricher(cacheDirectory: fixture.cacheURL)

    let enrichment = try await enricher.enrich(fixture.asset)

    #expect(enrichment.exif.cameraMake == "Nivlo Camera Co.")
    #expect(enrichment.exif.cameraModel == "Local One")
    #expect(enrichment.exif.orientation == 1)
  }

  @Test("writes a bounded thumbnail without changing the original")
  func writesThumbnailWithoutChangingOriginal() async throws {
    let fixture = try ImagingFixture(width: 1200, height: 800)
    let original = try Data(contentsOf: fixture.imageURL)
    let enricher = ImageEnricher(
      cacheDirectory: fixture.cacheURL,
      thumbnailMaxPixelSize: 320
    )

    let enrichment = try await enricher.enrich(fixture.asset)
    let thumbnailDimensions = try imageDimensions(at: enrichment.thumbnailURL)

    #expect(FileManager.default.fileExists(atPath: enrichment.thumbnailURL.path))
    #expect(max(thumbnailDimensions.width, thumbnailDimensions.height) <= 320)
    #expect(try Data(contentsOf: fixture.imageURL) == original)
  }

  @Test("reports an unreadable image without creating derived output")
  func rejectsCorruptImage() async throws {
    let fixture = try ImagingFixture()
    try Data("not an image".utf8).write(to: fixture.imageURL)
    let enricher = ImageEnricher(cacheDirectory: fixture.cacheURL)

    await #expect(throws: ImageEnricherError.self) {
      try await enricher.enrich(fixture.asset)
    }

    #expect(!FileManager.default.fileExists(atPath: fixture.cacheURL.path))
  }

  @Test("rejects a file that changed after the scan snapshot")
  func rejectsChangedSourceSnapshot() async throws {
    let fixture = try ImagingFixture()
    let staleAsset = fixture.asset
    let handle = try FileHandle(forWritingTo: fixture.imageURL)
    defer {
      try? handle.close()
    }
    try handle.seekToEnd()
    try handle.write(contentsOf: Data([0x00, 0x01, 0x02]))
    let enricher = ImageEnricher(cacheDirectory: fixture.cacheURL)

    await #expect(throws: ImageEnricherError.sourceChanged(fixture.imageURL)) {
      try await enricher.enrich(staleAsset)
    }

    #expect(!FileManager.default.fileExists(atPath: fixture.cacheURL.path))
  }
}

private struct ImagingFixture {
  let rootURL: URL
  let imageURL: URL
  let cacheURL: URL
  let asset: ImageAsset

  init(width: Int = 16, height: Int = 12) throws {
    rootURL = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    imageURL = rootURL.appending(path: "source.png")
    cacheURL = rootURL.appending(path: "cache", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
    try writeFixtureImage(at: imageURL, width: width, height: height)
    asset = ImageAsset(
      id: AssetID(volumeIdentifier: "volume", fileIdentifier: "source"),
      url: imageURL,
      filename: imageURL.lastPathComponent,
      contentType: UTType.png.identifier,
      fileSize: Int64(try Data(contentsOf: imageURL).count),
      createdAt: nil,
      modifiedAt: nil,
      pixelWidth: width,
      pixelHeight: height
    )
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
    throw ImagingFixtureError.creationFailed
  }
  context.setFillColor(CGColor(red: 0.1, green: 0.2, blue: 0.8, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width / 2, height: height))
  context.setFillColor(CGColor(red: 0.9, green: 0.7, blue: 0.1, alpha: 1))
  context.fill(
    CGRect(x: width / 2, y: 0, width: width - width / 2, height: height)
  )
  guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else {
    throw ImagingFixtureError.creationFailed
  }
  let properties: [CFString: Any] = [
    kCGImagePropertyOrientation: 1,
    kCGImagePropertyTIFFDictionary: [
      kCGImagePropertyTIFFMake: "Nivlo Camera Co.",
      kCGImagePropertyTIFFModel: "Local One",
    ],
  ]
  CGImageDestinationAddImage(destination, image, properties as CFDictionary)
  guard CGImageDestinationFinalize(destination) else {
    throw ImagingFixtureError.creationFailed
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
    throw ImagingFixtureError.creationFailed
  }
  return (width, height)
}

private enum ImagingFixtureError: Error {
  case creationFailed
}
