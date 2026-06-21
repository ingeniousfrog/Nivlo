import CryptoKit
import Foundation
import ImageIO
import NivloDomain
import UniformTypeIdentifiers
import Vision

public enum ImageEnricherError: Error, Equatable, LocalizedError, Sendable {
  case sourceChanged(URL)
  case unreadableImage(URL)
  case thumbnailCreationFailed(URL)
  case thumbnailWriteFailed(URL)

  public var errorDescription: String? {
    switch self {
    case .sourceChanged(let url):
      "The source changed while indexing \(url.lastPathComponent)."
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
  private let textRecognizer: any ImageTextRecognizing
  private let now: @Sendable () -> Date

  public init(
    cacheDirectory: URL,
    thumbnailMaxPixelSize: Int = 512,
    textRecognizer: any ImageTextRecognizing = VisionImageTextRecognizer(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.cacheDirectory = cacheDirectory.standardizedFileURL
    self.thumbnailMaxPixelSize = max(1, thumbnailMaxPixelSize)
    self.textRecognizer = textRecognizer
    self.now = now
  }

  public func enrich(_ asset: ImageAsset) async throws -> AssetEnrichment {
    try validateSourceStillMatches(asset)
    let exactHash = try sha256(at: asset.url)
    try validateSourceStillMatches(asset)
    guard let source = CGImageSourceCreateWithURL(asset.url as CFURL, nil) else {
      throw ImageEnricherError.unreadableImage(asset.url)
    }
    let perceptualHash = try differenceHash(source: source, url: asset.url)
    let thumbnailURL = try writeThumbnail(
      source: source,
      exactHash: exactHash,
      sourceURL: asset.url
    )
    let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    let ocrText = await recognizeText(in: image)
    let dominantColors = dominantColorBuckets(source: source)
    try validateSourceStillMatches(asset)
    return AssetEnrichment(
      assetID: asset.id,
      exactHash: exactHash,
      perceptualHash: perceptualHash,
      thumbnailURL: thumbnailURL,
      exif: extractEXIF(
        source: source,
        ocrText: ocrText,
        dominantColors: dominantColors
      ),
      indexedAt: now()
    )
  }

  private func validateSourceStillMatches(_ asset: ImageAsset) throws {
    let values = try asset.url.resourceValues(
      forKeys: [.fileSizeKey, .contentModificationDateKey]
    )
    guard Int64(values.fileSize ?? -1) == asset.fileSize else {
      throw ImageEnricherError.sourceChanged(asset.url)
    }
    if let expectedDate = asset.modifiedAt,
      values.contentModificationDate != expectedDate
    {
      throw ImageEnricherError.sourceChanged(asset.url)
    }
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

  private func extractEXIF(
    source: CGImageSource,
    ocrText: String?,
    dominantColors: [String]
  ) -> AssetEXIF {
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
      exposureTime: number(exif?[kCGImagePropertyExifExposureTime])?.doubleValue,
      ocrText: ocrText,
      dominantColors: dominantColors
    )
  }

  private func recognizeText(in image: CGImage?) async -> String? {
    guard let image else {
      return nil
    }
    do {
      return try await textRecognizer.recognizeText(in: image)
    } catch {
      return nil
    }
  }

  private func dominantColorBuckets(source: CGImageSource) -> [String] {
    let options: [CFString: Any] = [
      kCGImageSourceCreateThumbnailFromImageAlways: true,
      kCGImageSourceThumbnailMaxPixelSize: 24,
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
        width: 24,
        height: 24,
        bitsPerComponent: 8,
        bytesPerRow: 24 * 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      return []
    }
    context.interpolationQuality = .medium
    context.draw(image, in: CGRect(x: 0, y: 0, width: 24, height: 24))
    guard let data = context.data else {
      return []
    }

    let pixels = data.bindMemory(to: UInt8.self, capacity: 24 * 24 * 4)
    var buckets: [String: Int] = [:]
    for index in stride(from: 0, to: 24 * 24 * 4, by: 4) {
      let red = quantizedChannel(pixels[index])
      let green = quantizedChannel(pixels[index + 1])
      let blue = quantizedChannel(pixels[index + 2])
      let hex = String(format: "#%02X%02X%02X", red, green, blue)
      buckets[hex, default: 0] += 1
    }
    return
      buckets
      .sorted {
        if $0.value == $1.value {
          return $0.key < $1.key
        }
        return $0.value > $1.value
      }
      .prefix(6)
      .map(\.key)
  }

  private func quantizedChannel(_ value: UInt8) -> UInt8 {
    UInt8((Int(value) / 32) * 32)
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

public protocol ImageTextRecognizing: Sendable {
  func recognizeText(in image: CGImage) async throws -> String?
}

public struct VisionImageTextRecognizer: ImageTextRecognizing {
  public init() {}

  public func recognizeText(in image: CGImage) async throws -> String? {
    try await Task.detached(priority: .utility) {
      let request = VNRecognizeTextRequest()
      request.recognitionLevel = .fast
      request.usesLanguageCorrection = false
      let handler = VNImageRequestHandler(cgImage: image)
      try handler.perform([request])
      let text = (request.results ?? [])
        .compactMap { $0.topCandidates(1).first?.string }
        .joined(separator: "\n")
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return text.isEmpty ? nil : text
    }.value
  }
}
