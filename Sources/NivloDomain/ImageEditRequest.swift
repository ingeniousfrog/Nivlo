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
  public var tint: Double
  public var highlights: Double
  public var shadows: Double
  public var clarity: Double
  public var vibrance: Double
  public var sharpness: Double
  public var noiseReduction: Double
  public var vignette: Double
  public var levels: [ImageColorChannel: ImageLevels]
  public var curves: [ImageColorChannel: ToneCurve]
  public var colorBands: [HSLColorBand: HSLBandAdjustment]

  public init(
    exposure: Double = 0,
    contrast: Double = 0,
    saturation: Double = 0,
    warmth: Double = 0,
    tint: Double = 0,
    highlights: Double = 0,
    shadows: Double = 0,
    clarity: Double = 0,
    vibrance: Double = 0,
    sharpness: Double = 0,
    noiseReduction: Double = 0,
    vignette: Double = 0,
    levels: [ImageColorChannel: ImageLevels] = [:],
    curves: [ImageColorChannel: ToneCurve] = [:],
    colorBands: [HSLColorBand: HSLBandAdjustment] = [:]
  ) {
    self.exposure = exposure
    self.contrast = contrast
    self.saturation = saturation
    self.warmth = warmth
    self.tint = tint
    self.highlights = highlights
    self.shadows = shadows
    self.clarity = clarity
    self.vibrance = vibrance
    self.sharpness = sharpness
    self.noiseReduction = noiseReduction
    self.vignette = vignette
    self.levels = levels
    self.curves = curves
    self.colorBands = colorBands
  }

  public static let neutral = ImageAdjustmentSettings()

  public var blackPoint: Double {
    get { levels[.rgb]?.blackPoint ?? 0 }
    set {
      let current = levels[.rgb] ?? .neutral
      levels[.rgb] = ImageLevels(
        blackPoint: newValue,
        whitePoint: current.whitePoint,
        gamma: current.gamma
      )
    }
  }

  public var whitePoint: Double {
    get { levels[.rgb]?.whitePoint ?? 1 }
    set {
      let current = levels[.rgb] ?? .neutral
      levels[.rgb] = ImageLevels(
        blackPoint: current.blackPoint,
        whitePoint: newValue,
        gamma: current.gamma
      )
    }
  }

  public var gamma: Double {
    get { levels[.rgb]?.gamma ?? 1 }
    set {
      let current = levels[.rgb] ?? .neutral
      levels[.rgb] = ImageLevels(
        blackPoint: current.blackPoint,
        whitePoint: current.whitePoint,
        gamma: newValue
      )
    }
  }

  private enum CodingKeys: String, CodingKey {
    case exposure
    case contrast
    case saturation
    case warmth
    case tint
    case highlights
    case shadows
    case clarity
    case vibrance
    case sharpness
    case noiseReduction
    case vignette
    case levels
    case curves
    case colorBands
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      exposure: try container.decodeIfPresent(Double.self, forKey: .exposure) ?? 0,
      contrast: try container.decodeIfPresent(Double.self, forKey: .contrast) ?? 0,
      saturation: try container.decodeIfPresent(Double.self, forKey: .saturation) ?? 0,
      warmth: try container.decodeIfPresent(Double.self, forKey: .warmth) ?? 0,
      tint: try container.decodeIfPresent(Double.self, forKey: .tint) ?? 0,
      highlights: try container.decodeIfPresent(Double.self, forKey: .highlights) ?? 0,
      shadows: try container.decodeIfPresent(Double.self, forKey: .shadows) ?? 0,
      clarity: try container.decodeIfPresent(Double.self, forKey: .clarity) ?? 0,
      vibrance: try container.decodeIfPresent(Double.self, forKey: .vibrance) ?? 0,
      sharpness: try container.decodeIfPresent(Double.self, forKey: .sharpness) ?? 0,
      noiseReduction: try container.decodeIfPresent(Double.self, forKey: .noiseReduction) ?? 0,
      vignette: try container.decodeIfPresent(Double.self, forKey: .vignette) ?? 0,
      levels:
        try container.decodeIfPresent([ImageColorChannel: ImageLevels].self, forKey: .levels)
        ?? [:],
      curves:
        try container.decodeIfPresent([ImageColorChannel: ToneCurve].self, forKey: .curves)
        ?? [:],
      colorBands:
        try container.decodeIfPresent(
          [HSLColorBand: HSLBandAdjustment].self,
          forKey: .colorBands
        ) ?? [:]
    )
  }
}

public enum ImageAnnotationKind: String, Codable, Sendable, Equatable {
  case text
  case rectangle
  case arrow
}

public struct NormalizedPoint: Equatable, Sendable, Codable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = min(max(x, 0), 1)
    self.y = min(max(y, 0), 1)
  }
}

public enum ArrowGeometry {
  public static func moving(
    start: NormalizedPoint,
    end: NormalizedPoint,
    translation: CGSize,
    canvasSize: CGSize
  ) -> (start: NormalizedPoint, end: NormalizedPoint) {
    guard canvasSize.width > 0, canvasSize.height > 0 else {
      return (start, end)
    }
    let dx = Double(translation.width / canvasSize.width)
    let dy = Double(translation.height / canvasSize.height)
    let minimumX = min(start.x, end.x)
    let maximumX = max(start.x, end.x)
    let minimumY = min(start.y, end.y)
    let maximumY = max(start.y, end.y)
    let clampedDX = min(max(dx, -minimumX), 1 - maximumX)
    let clampedDY = min(max(dy, -minimumY), 1 - maximumY)
    return (
      NormalizedPoint(x: start.x + clampedDX, y: start.y + clampedDY),
      NormalizedPoint(x: end.x + clampedDX, y: end.y + clampedDY)
    )
  }

  public static func bounds(
    start: NormalizedPoint,
    end: NormalizedPoint,
    padding: Double = 0.02
  ) -> NormalizedCropRect {
    let left = max(0, min(start.x, end.x) - padding)
    let top = max(0, min(start.y, end.y) - padding)
    let right = min(1, max(start.x, end.x) + padding)
    let bottom = min(1, max(start.y, end.y) + padding)
    return NormalizedCropRect(
      x: left,
      y: top,
      width: max(0.01, right - left),
      height: max(0.01, bottom - top)
    )
  }
}

public enum AnnotationGeometry {
  public static func rotationDegrees(center: CGPoint, handle: CGPoint) -> Double {
    let radians = atan2(handle.y - center.y, handle.x - center.x) + .pi / 2
    return Double(radians * 180 / .pi)
  }

  public static func localTranslation(
    _ translation: CGSize,
    rotationDegrees: Double
  ) -> CGSize {
    let radians = CGFloat(rotationDegrees * .pi / 180)
    return CGSize(
      width: translation.width * cos(radians) + translation.height * sin(radians),
      height: -translation.width * sin(radians) + translation.height * cos(radians)
    )
  }

  public static func rotating(
    point: CGPoint,
    around center: CGPoint,
    degrees: Double
  ) -> CGPoint {
    let radians = CGFloat(degrees * .pi / 180)
    let dx = point.x - center.x
    let dy = point.y - center.y
    return CGPoint(
      x: center.x + dx * cos(radians) - dy * sin(radians),
      y: center.y + dx * sin(radians) + dy * cos(radians)
    )
  }
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
  case localAdjustments
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
    EditorLayer(kind: .localAdjustments),
    EditorLayer(kind: .mask),
    EditorLayer(kind: .annotations),
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
  public var rotationDegrees: Double
  public var arrowStart: NormalizedPoint
  public var arrowEnd: NormalizedPoint

  private enum CodingKeys: String, CodingKey {
    case id
    case kind
    case text
    case normalizedRect
    case textStyle
    case rectangleStyle
    case arrowStyle
    case rotationDegrees
    case arrowStart
    case arrowEnd
  }

  public init(
    id: UUID = UUID(),
    kind: ImageAnnotationKind,
    text: String = "",
    normalizedRect: NormalizedCropRect,
    textStyle: TextAnnotationStyle = TextAnnotationStyle(),
    rectangleStyle: RectangleAnnotationStyle = RectangleAnnotationStyle(),
    arrowStyle: ArrowAnnotationStyle = ArrowAnnotationStyle(),
    rotationDegrees: Double = 0,
    arrowStart: NormalizedPoint? = nil,
    arrowEnd: NormalizedPoint? = nil
  ) {
    self.id = id
    self.kind = kind
    self.text = text
    self.normalizedRect = normalizedRect
    self.textStyle = textStyle
    self.rectangleStyle = rectangleStyle
    self.arrowStyle = arrowStyle
    self.rotationDegrees = rotationDegrees
    self.arrowStart =
      arrowStart
      ?? NormalizedPoint(
        x: normalizedRect.x,
        y: normalizedRect.y + normalizedRect.height
      )
    self.arrowEnd =
      arrowEnd
      ?? NormalizedPoint(
        x: normalizedRect.x + normalizedRect.width,
        y: normalizedRect.y
      )
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let normalizedRect = try container.decode(NormalizedCropRect.self, forKey: .normalizedRect)

    self.init(
      id: try container.decode(UUID.self, forKey: .id),
      kind: try container.decode(ImageAnnotationKind.self, forKey: .kind),
      text: try container.decode(String.self, forKey: .text),
      normalizedRect: normalizedRect,
      textStyle: try container.decode(TextAnnotationStyle.self, forKey: .textStyle),
      rectangleStyle: try container.decode(RectangleAnnotationStyle.self, forKey: .rectangleStyle),
      arrowStyle: try container.decode(ArrowAnnotationStyle.self, forKey: .arrowStyle),
      rotationDegrees: try container.decodeIfPresent(Double.self, forKey: .rotationDegrees) ?? 0,
      arrowStart: try container.decodeIfPresent(NormalizedPoint.self, forKey: .arrowStart),
      arrowEnd: try container.decodeIfPresent(NormalizedPoint.self, forKey: .arrowEnd)
    )
  }
}

public struct ImageEditSnapshot: Sendable, Equatable, Codable {
  public var cropRect: NormalizedCropRect
  public var quarterTurns: Int
  public var flippedHorizontally: Bool
  public var adjustments: ImageAdjustmentSettings
  public var annotations: [ImageAnnotation]
  public var maskStrokes: [MaskStroke]
  public var localAdjustments: [LocalImageAdjustment]
  public var layers: [EditorLayer]

  public init(
    cropRect: NormalizedCropRect = .full,
    quarterTurns: Int = 0,
    flippedHorizontally: Bool = false,
    adjustments: ImageAdjustmentSettings = .neutral,
    annotations: [ImageAnnotation] = [],
    maskStrokes: [MaskStroke] = [],
    localAdjustments: [LocalImageAdjustment] = [],
    layers: [EditorLayer] = EditorLayer.defaults
  ) {
    self.cropRect = cropRect
    self.quarterTurns = quarterTurns
    self.flippedHorizontally = flippedHorizontally
    self.adjustments = adjustments
    self.annotations = annotations
    self.maskStrokes = maskStrokes
    self.localAdjustments = localAdjustments
    self.layers = layers
  }

  private enum CodingKeys: String, CodingKey {
    case cropRect
    case quarterTurns
    case flippedHorizontally
    case adjustments
    case annotations
    case maskStrokes
    case localAdjustments
    case layers
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      cropRect: try container.decodeIfPresent(NormalizedCropRect.self, forKey: .cropRect) ?? .full,
      quarterTurns: try container.decodeIfPresent(Int.self, forKey: .quarterTurns) ?? 0,
      flippedHorizontally:
        try container.decodeIfPresent(Bool.self, forKey: .flippedHorizontally) ?? false,
      adjustments:
        try container.decodeIfPresent(ImageAdjustmentSettings.self, forKey: .adjustments)
        ?? .neutral,
      annotations:
        try container.decodeIfPresent([ImageAnnotation].self, forKey: .annotations) ?? [],
      maskStrokes:
        try container.decodeIfPresent([MaskStroke].self, forKey: .maskStrokes) ?? [],
      localAdjustments:
        try container.decodeIfPresent(
          [LocalImageAdjustment].self,
          forKey: .localAdjustments
        ) ?? [],
      layers:
        try container.decodeIfPresent([EditorLayer].self, forKey: .layers)
        ?? EditorLayer.defaults
    )
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
  public var localAdjustments: [LocalImageAdjustment]
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
    localAdjustments: [LocalImageAdjustment] = [],
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
    self.localAdjustments = localAdjustments
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
