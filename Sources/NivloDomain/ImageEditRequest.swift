import Foundation

public struct NormalizedCropRect: Equatable, Sendable, Codable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  public init(x: Double, y: Double, width: Double, height: Double) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }

  public static let full = NormalizedCropRect(x: 0, y: 0, width: 1, height: 1)

  public func clamped() -> NormalizedCropRect {
    let clampedWidth = min(max(width, 0.01), 1)
    let clampedHeight = min(max(height, 0.01), 1)
    let clampedX = min(max(x, 0), 1 - clampedWidth)
    let clampedY = min(max(y, 0), 1 - clampedHeight)
    return NormalizedCropRect(
      x: clampedX,
      y: clampedY,
      width: clampedWidth,
      height: clampedHeight
    )
  }

  public func pixelRect(imageWidth: Int, imageHeight: Int) -> (x: Int, y: Int, width: Int, height: Int) {
    let clamped = clamped()
    let width = max(1, Int((clamped.width * Double(imageWidth)).rounded()))
    let height = max(1, Int((clamped.height * Double(imageHeight)).rounded()))
    let x = max(0, Int((clamped.x * Double(imageWidth)).rounded()))
    let y = max(0, Int((clamped.y * Double(imageHeight)).rounded()))
    return (x: x, y: y, width: width, height: height)
  }
}

public struct ImageAdjustmentSettings: Equatable, Sendable, Codable {
  public var exposure: Double
  public var contrast: Double
  public var saturation: Double
  public var warmth: Double

  public init(
    exposure: Double = 0,
    contrast: Double = 0,
    saturation: Double = 0,
    warmth: Double = 0
  ) {
    self.exposure = exposure
    self.contrast = contrast
    self.saturation = saturation
    self.warmth = warmth
  }

  public static let neutral = ImageAdjustmentSettings()
}

public enum ImageAnnotationKind: String, Codable, Sendable, Equatable {
  case text
  case rectangle
  case arrow
}

public struct MaskStroke: Identifiable, Equatable, Sendable, Codable {
  public let id: UUID
  public var normalizedRect: NormalizedCropRect

  public init(
    id: UUID = UUID(),
    normalizedRect: NormalizedCropRect
  ) {
    self.id = id
    self.normalizedRect = normalizedRect
  }
}

public enum EditorLayerKind: String, Codable, Sendable, Equatable {
  case background
  case adjustments
  case annotations
  case mask
}

public struct EditorLayer: Identifiable, Equatable, Sendable, Codable {
  public let id: UUID
  public var kind: EditorLayerKind
  public var isVisible: Bool

  public init(id: UUID = UUID(), kind: EditorLayerKind, isVisible: Bool = true) {
    self.id = id
    self.kind = kind
    self.isVisible = isVisible
  }

  public static let defaults: [EditorLayer] = [
    EditorLayer(kind: .background),
    EditorLayer(kind: .adjustments),
    EditorLayer(kind: .annotations),
    EditorLayer(kind: .mask),
  ]
}

public struct ImageAnnotation: Identifiable, Equatable, Sendable, Codable {
  public let id: UUID
  public var kind: ImageAnnotationKind
  public var text: String
  public var normalizedRect: NormalizedCropRect

  public init(
    id: UUID = UUID(),
    kind: ImageAnnotationKind,
    text: String = "",
    normalizedRect: NormalizedCropRect
  ) {
    self.id = id
    self.kind = kind
    self.text = text
    self.normalizedRect = normalizedRect
  }
}

public struct ImageEditRequest: Sendable, Equatable {
  public let sourceURL: URL
  public let outputURL: URL
  public var cropRect: NormalizedCropRect
  public var quarterTurns: Int
  public var flippedHorizontally: Bool
  public var adjustments: ImageAdjustmentSettings
  public var annotations: [ImageAnnotation]
  public var maskStrokes: [MaskStroke]
  public var layers: [EditorLayer]
  public var format: PicxOutputFormat
  public var quality: Int
  public var preset: PicxPreset?
  public var maxWidth: Int?
  public var maxHeight: Int?
  public var targetSizeBytes: Int?

  public init(
    sourceURL: URL,
    outputURL: URL,
    cropRect: NormalizedCropRect = .full,
    quarterTurns: Int = 0,
    flippedHorizontally: Bool = false,
    adjustments: ImageAdjustmentSettings = .neutral,
    annotations: [ImageAnnotation] = [],
    maskStrokes: [MaskStroke] = [],
    layers: [EditorLayer] = EditorLayer.defaults,
    format: PicxOutputFormat = .webp,
    quality: Int = 82,
    preset: PicxPreset? = nil,
    maxWidth: Int? = nil,
    maxHeight: Int? = nil,
    targetSizeBytes: Int? = nil
  ) {
    self.sourceURL = sourceURL
    self.outputURL = outputURL
    self.cropRect = cropRect
    self.quarterTurns = quarterTurns
    self.flippedHorizontally = flippedHorizontally
    self.adjustments = adjustments
    self.annotations = annotations
    self.maskStrokes = maskStrokes
    self.layers = layers
    self.format = format
    self.quality = quality
    self.preset = preset
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.targetSizeBytes = targetSizeBytes
  }
}

public enum PicxOutputFormat: String, Sendable, Codable, CaseIterable {
  case webp
  case avif
  case jpg
  case png

  public var cliValue: String { rawValue }
}

public enum PicxPreset: String, Sendable, Codable, CaseIterable {
  case web
  case blog
  case avatar
  case lossless
}

public struct PicxOptimizeRequest: Sendable, Equatable {
  public let sourceURL: URL
  public let outputURL: URL
  public var format: PicxOutputFormat
  public var quality: Int
  public var preset: PicxPreset?
  public var maxWidth: Int?
  public var maxHeight: Int?
  public var targetSizeBytes: Int?

  public init(
    sourceURL: URL,
    outputURL: URL,
    format: PicxOutputFormat = .webp,
    quality: Int = 82,
    preset: PicxPreset? = nil,
    maxWidth: Int? = nil,
    maxHeight: Int? = nil,
    targetSizeBytes: Int? = nil
  ) {
    self.sourceURL = sourceURL
    self.outputURL = outputURL
    self.format = format
    self.quality = quality
    self.preset = preset
    self.maxWidth = maxWidth
    self.maxHeight = maxHeight
    self.targetSizeBytes = targetSizeBytes
  }
}

public struct PicxOptimizeResult: Sendable, Equatable {
  public let sourceURL: URL
  public let outputURL: URL
  public let originalSize: Int64
  public let outputSize: Int64
  public let savingsRatio: Double

  public init(
    sourceURL: URL,
    outputURL: URL,
    originalSize: Int64,
    outputSize: Int64,
    savingsRatio: Double
  ) {
    self.sourceURL = sourceURL
    self.outputURL = outputURL
    self.originalSize = originalSize
    self.outputSize = outputSize
    self.savingsRatio = savingsRatio
  }
}
