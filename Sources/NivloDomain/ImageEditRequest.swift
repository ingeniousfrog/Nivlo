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

  public func pixelRect(imageWidth: Int, imageHeight: Int) -> (
    x: Int, y: Int, width: Int, height: Int
  ) {
    let clamped = clamped()
    let width = max(1, Int((clamped.width * Double(imageWidth)).rounded()))
    let height = max(1, Int((clamped.height * Double(imageHeight)).rounded()))
    let x = max(0, Int((clamped.x * Double(imageWidth)).rounded()))
    let y = max(0, Int((clamped.y * Double(imageHeight)).rounded()))
    return (x: x, y: y, width: width, height: height)
  }

  /// Maps a top-left normalized rect into Core Image's bottom-left coordinate space.
  public func ciCropCGRect(imageWidth: CGFloat, imageHeight: CGFloat) -> CGRect {
    let value = clamped()
    let x = value.x * imageWidth
    let y = (1 - value.y - value.height) * imageHeight
    let width = value.width * imageWidth
    let height = value.height * imageHeight
    return CGRect(
      origin: CGPoint(x: x, y: y),
      size: CGSize(width: width, height: height)
    )
  }

  public var isEffectivelyFull: Bool {
    let value = clamped()
    return value.x <= 0.001 && value.y <= 0.001 && value.width >= 0.999 && value.height >= 0.999
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

public struct RGBAColor: Equatable, Sendable, Codable {
  public var red: Double
  public var green: Double
  public var blue: Double
  public var alpha: Double

  public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
    self.red = min(max(red, 0), 1)
    self.green = min(max(green, 0), 1)
    self.blue = min(max(blue, 0), 1)
    self.alpha = min(max(alpha, 0), 1)
  }

  public static let white = RGBAColor(red: 1, green: 1, blue: 1)
  public static let black = RGBAColor(red: 0, green: 0, blue: 0)
  public static let red = RGBAColor(red: 0.95, green: 0.2, blue: 0.2)
  public static let blue = RGBAColor(red: 0.1, green: 0.45, blue: 0.95)
  public static let yellow = RGBAColor(red: 1, green: 0.78, blue: 0.08)
  public static let orange = RGBAColor(red: 1, green: 0.45, blue: 0.08)
  public static let clear = RGBAColor(red: 0, green: 0, blue: 0, alpha: 0)
}

public enum AnnotationLineStyle: String, Codable, Sendable, Equatable, CaseIterable {
  case solid
  case dashed
  case dashDot
}

public struct TextAnnotationStyle: Equatable, Sendable, Codable {
  public var fontName: String
  public var fontSize: Double
  public var color: RGBAColor
  public var isBold: Bool
  public var isItalic: Bool

  public init(
    fontName: String = "Helvetica",
    fontSize: Double = 28,
    color: RGBAColor = .white,
    isBold: Bool = true,
    isItalic: Bool = false
  ) {
    self.fontName = fontName
    self.fontSize = max(8, fontSize)
    self.color = color
    self.isBold = isBold
    self.isItalic = isItalic
  }
}

public struct RectangleAnnotationStyle: Equatable, Sendable, Codable {
  public var strokeColor: RGBAColor
  public var fillColor: RGBAColor
  public var lineWidth: Double
  public var lineStyle: AnnotationLineStyle

  public init(
    strokeColor: RGBAColor = .yellow,
    fillColor: RGBAColor = .clear,
    lineWidth: Double = 4,
    lineStyle: AnnotationLineStyle = .solid
  ) {
    self.strokeColor = strokeColor
    self.fillColor = fillColor
    self.lineWidth = max(1, lineWidth)
    self.lineStyle = lineStyle
  }
}

public enum ArrowDirection: String, Codable, Sendable, Equatable, CaseIterable {
  case forward
  case backward
  case both
}

public struct ArrowAnnotationStyle: Equatable, Sendable, Codable {
  public var color: RGBAColor
  public var lineWidth: Double
  public var direction: ArrowDirection

  public init(
    color: RGBAColor = .orange,
    lineWidth: Double = 4,
    direction: ArrowDirection = .forward
  ) {
    self.color = color
    self.lineWidth = max(1, lineWidth)
    self.direction = direction
  }
}

public struct MaskBrushPoint: Equatable, Sendable, Codable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

public enum MaskStrokeOperation: String, Equatable, Sendable, Codable {
  case paint
  case erase
}

public struct MaskStroke: Identifiable, Equatable, Sendable, Codable {
  public let id: UUID
  public var points: [MaskBrushPoint]
  public var brushRadius: Double
  public var operation: MaskStrokeOperation

  public init(
    id: UUID = UUID(),
    points: [MaskBrushPoint] = [],
    brushRadius: Double = 0.03,
    operation: MaskStrokeOperation = .paint
  ) {
    self.id = id
    self.points = points
    self.brushRadius = brushRadius
    self.operation = operation
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
  public var textStyle: TextAnnotationStyle
  public var rectangleStyle: RectangleAnnotationStyle
  public var arrowStyle: ArrowAnnotationStyle

  public init(
    id: UUID = UUID(),
    kind: ImageAnnotationKind,
    text: String = "",
    normalizedRect: NormalizedCropRect,
    textStyle: TextAnnotationStyle = TextAnnotationStyle(),
    rectangleStyle: RectangleAnnotationStyle = RectangleAnnotationStyle(),
    arrowStyle: ArrowAnnotationStyle = ArrowAnnotationStyle()
  ) {
    self.id = id
    self.kind = kind
    self.text = text
    self.normalizedRect = normalizedRect
    self.textStyle = textStyle
    self.rectangleStyle = rectangleStyle
    self.arrowStyle = arrowStyle
  }
}

public struct ImageEditSnapshot: Sendable, Equatable {
  public var cropRect: NormalizedCropRect
  public var quarterTurns: Int
  public var flippedHorizontally: Bool
  public var adjustments: ImageAdjustmentSettings
  public var annotations: [ImageAnnotation]
  public var maskStrokes: [MaskStroke]
  public var layers: [EditorLayer]

  public init(
    cropRect: NormalizedCropRect = .full,
    quarterTurns: Int = 0,
    flippedHorizontally: Bool = false,
    adjustments: ImageAdjustmentSettings = .neutral,
    annotations: [ImageAnnotation] = [],
    maskStrokes: [MaskStroke] = [],
    layers: [EditorLayer] = EditorLayer.defaults
  ) {
    self.cropRect = cropRect
    self.quarterTurns = quarterTurns
    self.flippedHorizontally = flippedHorizontally
    self.adjustments = adjustments
    self.annotations = annotations
    self.maskStrokes = maskStrokes
    self.layers = layers
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
