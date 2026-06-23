import Foundation

public struct AssetPreviewDetails: Equatable, Sendable {
  public let filename: String
  public let format: String
  public let mediaKind: AssetMediaKind
  public let dimensions: String?
  public let megapixels: String?
  public let aspectRatio: String?
  public let fileSize: String
  public let createdAt: Date?
  public let modifiedAt: Date?
  public let capturedAt: Date?
  public let camera: String?
  public let lens: String?
  public let exposure: String?
  public let dominantColors: [String]
  public let keywords: [String]
  public let path: String
  public let duration: String?
  public let frameRate: String?
  public let hasAudio: Bool?
  public let videoCodec: String?
  public let audioCodec: String?

  public init(
    asset: ImageAsset,
    enrichment: AssetEnrichment? = nil,
    videoProbe: VideoProbeInfo? = nil
  ) {
    filename = asset.filename
    format = Self.formatTitle(for: asset.contentType)
    mediaKind = asset.mediaKind

    let width = asset.pixelWidth ?? videoProbe?.width.nilIfZero
    let height = asset.pixelHeight ?? videoProbe?.height.nilIfZero

    dimensions = Self.dimensionsTitle(width: width, height: height)
    megapixels = Self.megapixelsTitle(width: width, height: height)
    aspectRatio = Self.aspectRatioTitle(width: width, height: height)
    fileSize = Self.fileSizeTitle(asset.fileSize)
    createdAt = asset.createdAt
    modifiedAt = asset.modifiedAt
    capturedAt = enrichment?.exif.capturedAt
    camera = Self.cameraTitle(
      make: enrichment?.exif.cameraMake,
      model: enrichment?.exif.cameraModel
    )
    lens = enrichment?.exif.lensModel?.trimmingCharacters(in: .whitespacesAndNewlines)
      .nilIfEmpty
    exposure = Self.exposureTitle(
      iso: enrichment?.exif.isoSpeed,
      aperture: enrichment?.exif.aperture,
      exposureTime: enrichment?.exif.exposureTime
    )
    dominantColors = enrichment?.exif.dominantColors ?? []
    keywords = enrichment?.exif.keywords ?? []
    path = asset.url.standardizedFileURL.path
    duration = videoProbe.flatMap { Self.durationTitle($0.durationSeconds) }
    frameRate = videoProbe.flatMap { Self.frameRateTitle($0.frameRate) }
    hasAudio = videoProbe?.hasAudio
    videoCodec = videoProbe?.videoCodec
    audioCodec = videoProbe?.hasAudio == true ? videoProbe?.audioCodec : nil
  }

  private static func formatTitle(for contentType: String) -> String {
    let suffix = contentType.components(separatedBy: ".").last ?? "image"
    return suffix.uppercased()
  }

  private static func dimensionsTitle(width: Int?, height: Int?) -> String? {
    guard let width, let height else {
      return nil
    }
    return "\(width) × \(height)"
  }

  private static func megapixelsTitle(width: Int?, height: Int?) -> String? {
    guard let width, let height, width > 0, height > 0 else {
      return nil
    }
    let megapixels = Double(width * height) / 1_000_000
    if megapixels < 0.1 {
      return String(format: "%.2f MP", megapixels)
    }
    return String(format: "%.1f MP", megapixels)
  }

  private static func aspectRatioTitle(width: Int?, height: Int?) -> String? {
    guard let width, let height, width > 0, height > 0 else {
      return nil
    }
    let gcd = greatestCommonDivisor(width, height)
    return "\(width / gcd):\(height / gcd)"
  }

  private static func fileSizeTitle(_ byteCount: Int64) -> String {
    ByteCountFormatter.string(
      fromByteCount: byteCount,
      countStyle: .file
    )
  }

  public static func durationTitle(_ seconds: Double) -> String? {
    guard seconds.isFinite, seconds > 0 else {
      return nil
    }
    let totalSeconds = Int(seconds.rounded())
    let hours = totalSeconds / 3_600
    let minutes = (totalSeconds % 3_600) / 60
    let secs = totalSeconds % 60
    if hours > 0 {
      return String(format: "%d:%02d:%02d", hours, minutes, secs)
    }
    return String(format: "%d:%02d", minutes, secs)
  }

  public static func frameRateTitle(_ frameRate: Double) -> String? {
    guard frameRate.isFinite, frameRate > 0 else {
      return nil
    }
    if frameRate.rounded() == frameRate {
      return String(format: "%.0f fps", frameRate)
    }
    return String(format: "%.2f fps", frameRate)
  }

  private static func cameraTitle(make: String?, model: String?) -> String? {
    let parts = [make, model]
      .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty }
    guard !parts.isEmpty else {
      return nil
    }
    return parts.joined(separator: " ")
  }

  private static func exposureTitle(
    iso: Int?,
    aperture: Double?,
    exposureTime: Double?
  ) -> String? {
    var parts: [String] = []
    if let aperture, aperture > 0 {
      parts.append(String(format: "f/%.1f", aperture))
    }
    if let exposureTime, exposureTime > 0 {
      parts.append(shutterSpeedTitle(exposureTime))
    }
    if let iso, iso > 0 {
      parts.append("ISO \(iso)")
    }
    return parts.nilIfEmpty?.joined(separator: " · ")
  }

  private static func shutterSpeedTitle(_ seconds: Double) -> String {
    if seconds >= 1 {
      return String(format: "%.1fs", seconds)
    }
    let denominator = Int((1 / seconds).rounded())
    return denominator > 0 ? "1/\(denominator)s" : String(format: "%.4fs", seconds)
  }

  private static func greatestCommonDivisor(_ lhs: Int, _ rhs: Int) -> Int {
    var a = abs(lhs)
    var b = abs(rhs)
    while b != 0 {
      let remainder = a % b
      a = b
      b = remainder
    }
    return max(a, 1)
  }
}

private extension String {
  var nilIfEmpty: String? {
    isEmpty ? nil : self
  }
}

private extension Int {
  var nilIfZero: Int? {
    self > 0 ? self : nil
  }
}

private extension Array where Element == String {
  var nilIfEmpty: [String]? {
    isEmpty ? nil : self
  }
}
