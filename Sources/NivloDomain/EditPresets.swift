import Foundation

public struct ImageAdjustmentPreset: Identifiable, Codable, Equatable, Sendable {
  public let id: String
  public var name: String
  public var settings: ImageAdjustmentSettings

  public init(id: String, name: String, settings: ImageAdjustmentSettings) {
    self.id = id
    self.name = name
    self.settings = settings
  }

  public static let builtIn: [ImageAdjustmentPreset] = [
    ImageAdjustmentPreset(id: "neutral", name: "Neutral", settings: .neutral),
    ImageAdjustmentPreset(
      id: "vivid",
      name: "Vivid",
      settings: ImageAdjustmentSettings(
        contrast: 0.08,
        saturation: 0.08,
        clarity: 0.2,
        vibrance: 0.35
      )
    ),
    ImageAdjustmentPreset(
      id: "soft",
      name: "Soft",
      settings: ImageAdjustmentSettings(
        contrast: -0.08,
        highlights: -0.15,
        shadows: 0.15,
        clarity: -0.12
      )
    ),
  ]
}

public struct ImageExportPreset: Identifiable, Codable, Equatable, Sendable {
  public let id: String
  public var name: String
  public var format: PicxOutputFormat
  public var quality: Int
  public var maxWidth: Int?
  public var maxHeight: Int?

  public init(
    id: String,
    name: String,
    format: PicxOutputFormat,
    quality: Int,
    maxWidth: Int? = nil,
    maxHeight: Int? = nil
  ) {
    self.id = id
    self.name = name
    self.format = format
    self.quality = min(max(quality, 1), 100)
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
  }

  public static let builtIn: [ImageExportPreset] = [
    ImageExportPreset(id: "web", name: "Web", format: .webp, quality: 82),
    ImageExportPreset(
      id: "social",
      name: "Social",
      format: .jpg,
      quality: 88,
      maxWidth: 2_048,
      maxHeight: 2_048
    ),
    ImageExportPreset(id: "lossless", name: "Lossless", format: .png, quality: 100),
  ]
}
