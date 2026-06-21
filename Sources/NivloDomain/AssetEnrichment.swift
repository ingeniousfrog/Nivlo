import Foundation

public struct AssetEXIF: Codable, Equatable, Sendable {
  public let cameraMake: String?
  public let cameraModel: String?
  public let lensModel: String?
  public let capturedAt: Date?
  public let orientation: Int?
  public let isoSpeed: Int?
  public let focalLength: Double?
  public let aperture: Double?
  public let exposureTime: Double?
  public let ocrText: String?
  public let keywords: [String]
  public let dominantColors: [String]

  public init(
    cameraMake: String?,
    cameraModel: String?,
    lensModel: String?,
    capturedAt: Date?,
    orientation: Int?,
    isoSpeed: Int?,
    focalLength: Double?,
    aperture: Double?,
    exposureTime: Double?,
    ocrText: String? = nil,
    keywords: [String] = [],
    dominantColors: [String] = []
  ) {
    self.cameraMake = cameraMake
    self.cameraModel = cameraModel
    self.lensModel = lensModel
    self.capturedAt = capturedAt
    self.orientation = orientation
    self.isoSpeed = isoSpeed
    self.focalLength = focalLength
    self.aperture = aperture
    self.exposureTime = exposureTime
    self.ocrText = ocrText
    self.keywords = keywords
    self.dominantColors = dominantColors
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cameraMake = try container.decodeIfPresent(String.self, forKey: .cameraMake)
    cameraModel = try container.decodeIfPresent(String.self, forKey: .cameraModel)
    lensModel = try container.decodeIfPresent(String.self, forKey: .lensModel)
    capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
    orientation = try container.decodeIfPresent(Int.self, forKey: .orientation)
    isoSpeed = try container.decodeIfPresent(Int.self, forKey: .isoSpeed)
    focalLength = try container.decodeIfPresent(Double.self, forKey: .focalLength)
    aperture = try container.decodeIfPresent(Double.self, forKey: .aperture)
    exposureTime = try container.decodeIfPresent(Double.self, forKey: .exposureTime)
    ocrText = try container.decodeIfPresent(String.self, forKey: .ocrText)
    keywords =
      try container.decodeIfPresent([String].self, forKey: .keywords) ?? []
    dominantColors =
      try container.decodeIfPresent([String].self, forKey: .dominantColors) ?? []
  }
}

public struct AssetEnrichment: Equatable, Sendable {
  public let assetID: AssetID
  public let exactHash: String
  public let perceptualHash: UInt64
  public let thumbnailURL: URL
  public let exif: AssetEXIF
  public let indexedAt: Date

  public init(
    assetID: AssetID,
    exactHash: String,
    perceptualHash: UInt64,
    thumbnailURL: URL,
    exif: AssetEXIF,
    indexedAt: Date
  ) {
    self.assetID = assetID
    self.exactHash = exactHash
    self.perceptualHash = perceptualHash
    self.thumbnailURL = thumbnailURL
    self.exif = exif
    self.indexedAt = indexedAt
  }
}

public protocol AssetEnrichmentRepository: Sendable {
  func enrichments() async throws -> [AssetEnrichment]
  func upsertEnrichments(_ enrichments: [AssetEnrichment]) async throws
}
