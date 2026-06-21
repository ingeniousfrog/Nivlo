import CryptoKit
import Foundation
import ImageIO
import NivloDomain
import UniformTypeIdentifiers

public enum ImageEnricherError: Error, LocalizedError, Sendable {
  case unreadableImage(URL)
  case thumbnailCreationFailed(URL)
  case thumbnailWriteFailed(URL)

  public var errorDescription: String? {
    switch self {
    case .unreadableImage(let url):
      "Could not read image data at \(url.path)."
    case .thumbnailCreationFailed(let url):
      "Could not create a thumbnail for \(url.lastPathComponent)."
    case .thumbnailWriteFailed(let url):
      "Could not write the thumbnail cache at \(url.path)."
    }
  }
}

public actor ImageEnricher: AssetImageEnriching {
  private let cacheDirectory: URL
  private let thumbnailMaxPixelSize: Int
  private let now: @Sendable () -> Date

  public init(
    cacheDirectory: URL,
    thumbnailMaxPixelSize: Int = 512,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.cacheDirectory = cacheDirectory.standardizedFileURL
    self.thumbnailMaxPixelSize = max(1, thumbnailMaxPixelSize)
    self.now = now
  }

  public func enrich(_ asset: ImageAsset) async throws -> AssetEnrichment {
    let exactHash = try sha256(at: asset.url)
    guard let source = CGImageSourceCreateWithURL(asset.url as CFURL, nil) else {
      throw ImageEnricherError.unreadableImage(asset.url)
    }
    let perceptualHash = try differenceHash(source: source, url: asset.url)
    let thumbnailURL = try writeThumbnail(
      source: source,
      exactHash: exactHash,
      sourceURL: asset.url
    )
    return AssetEnrichment(
      assetID: asset.id,
      exactHash: exactHash,
      perceptualHash: perceptualHash,
      thumbnailURL: thumbnailURL,
      exif: extractEXIF(source: source),
      indexedAt: now()
    )
  }

  private func sha256(at url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer {
      try? handle.close()
    }

    var hasher = SHA256()
    while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
      hasher.update(data: chunk)
    }
    return hasher.finalize()
      .map { String(format: "%02x", $0) }
      .joined()
  }

  private func differenceHash(
    source: CGImageSource,
    url: URL
  ) throws -> UInt64 {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 9,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      ),
      let context = CGContext(
        data: nil,
        width: 9,
        height: 8,
        bitsPerComponent: 8,
        bytesPerRow: 9,
        space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
      )
    else {
      throw ImageEnricherError.unreadableImage(url)
    }

    context.interpolationQuality = .high
    context.draw(image, in: CGRect(x: 0, y: 0, width: 9, height: 8))
    guard let data = context.data else {
      throw ImageEnricherError.unreadableImage(url)
    }
    let pixels = data.bindMemory(to: UInt8.self, capacity: 72)
    var hash: UInt64 = 0
    for row in 0..<8 {
      for column in 0..<8 {
        hash <<= 1
        if pixels[row * 9 + column] > pixels[row * 9 + column + 1] {
          hash |= 1
        }
      }
    }
    return hash
  }

  private func writeThumbnail(
    source: CGImageSource,
    exactHash: String,
    sourceURL: URL
  ) throws -> URL {
    try FileManager.default.createDirectory(
      at: cacheDirectory,
      withIntermediateDirectories: true
    )
    let thumbnailURL = cacheDirectory.appending(path: "\(exactHash).jpg")
    if FileManager.default.fileExists(atPath: thumbnailURL.path) {
      return thumbnailURL
    }

    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: thumbnailMaxPixelSize,
      kCGImageSourceCreateThumbnailWithTransform: true,
    ]
    guard
      let thumbnail = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        options as CFDictionary
      )
    else {
      throw ImageEnricherError.thumbnailCreationFailed(sourceURL)
    }

    let temporaryURL = cacheDirectory.appending(
      path: ".\(UUID().uuidString).jpg"
    )
    guard
      let destination = CGImageDestinationCreateWithURL(
        temporaryURL as CFURL,
        UTType.jpeg.identifier as CFString,
        1,
        nil
      )
    else {
      throw ImageEnricherError.thumbnailWriteFailed(temporaryURL)
    }
    CGImageDestinationAddImage(
      destination,
      thumbnail,
      [
        kCGImageDestinationLossyCompressionQuality: 0.82
      ] as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: temporaryURL)
      throw ImageEnricherError.thumbnailWriteFailed(temporaryURL)
    }
    do {
      try FileManager.default.moveItem(
        at: temporaryURL,
        to: thumbnailURL
      )
    } catch {
      try? FileManager.default.removeItem(at: temporaryURL)
      if !FileManager.default.fileExists(atPath: thumbnailURL.path) {
        throw ImageEnricherError.thumbnailWriteFailed(thumbnailURL)
      }
    }
    return thumbnailURL
  }

  private func extractEXIF(source: CGImageSource) -> AssetEXIF {
    let properties =
      CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any]
    let tiff = properties?[kCGImagePropertyTIFFDictionary] as? [CFString: Any]
    let exif = properties?[kCGImagePropertyExifDictionary] as? [CFString: Any]
    return AssetEXIF(
      cameraMake: tiff?[kCGImagePropertyTIFFMake] as? String,
      cameraModel: tiff?[kCGImagePropertyTIFFModel] as? String,
      lensModel: exif?[kCGImagePropertyExifLensModel] as? String,
      capturedAt: capturedAt(exif: exif, tiff: tiff),
      orientation: number(properties?[kCGImagePropertyOrientation])?.intValue,
      isoSpeed: isoSpeed(exif?[kCGImagePropertyExifISOSpeedRatings]),
      focalLength: number(exif?[kCGImagePropertyExifFocalLength])?.doubleValue,
      aperture: number(exif?[kCGImagePropertyExifFNumber])?.doubleValue,
      exposureTime: number(exif?[kCGImagePropertyExifExposureTime])?.doubleValue
    )
  }

  private func capturedAt(
    exif: [CFString: Any]?,
    tiff: [CFString: Any]?
  ) -> Date? {
    let value =
      exif?[kCGImagePropertyExifDateTimeOriginal] as? String
      ?? tiff?[kCGImagePropertyTIFFDateTime] as? String
    guard let value else {
      return nil
    }
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.dateFormat = "yyyy:MM:dd HH:mm:ss"
    return formatter.date(from: value)
  }

  private func isoSpeed(_ value: Any?) -> Int? {
    if let values = value as? [NSNumber] {
      return values.first?.intValue
    }
    return number(value)?.intValue
  }

  private func number(_ value: Any?) -> NSNumber? {
    value as? NSNumber
  }
}
