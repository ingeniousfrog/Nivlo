import Foundation

public enum ImageColorChannel: String, Codable, CaseIterable, Sendable {
  case rgb
  case red
  case green
  case blue
}

public struct ImageLevels: Codable, Equatable, Sendable {
  public var blackPoint: Double
  public var whitePoint: Double
  public var gamma: Double

  public init(
    blackPoint: Double = 0,
    whitePoint: Double = 1,
    gamma: Double = 1
  ) {
    let black = min(max(blackPoint, 0), 0.99)
    let white = min(max(whitePoint, 0.01), 1)
    self.blackPoint = min(black, white - 0.01)
    self.whitePoint = max(white, self.blackPoint + 0.01)
    self.gamma = min(max(gamma, 0.1), 10)
  }

  public static let neutral = ImageLevels()

  private enum CodingKeys: String, CodingKey {
    case blackPoint
    case whitePoint
    case gamma
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      blackPoint: try container.decode(Double.self, forKey: .blackPoint),
      whitePoint: try container.decode(Double.self, forKey: .whitePoint),
      gamma: try container.decode(Double.self, forKey: .gamma)
    )
  }
}

public struct ToneCurvePoint: Codable, Equatable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = min(max(x, 0), 1)
    self.y = min(max(y, 0), 1)
  }

  private enum CodingKeys: String, CodingKey {
    case x
    case y
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      x: try container.decode(Double.self, forKey: .x),
      y: try container.decode(Double.self, forKey: .y)
    )
  }
}

public struct ToneCurve: Codable, Equatable, Sendable {
  public var points: [ToneCurvePoint]

  public init(
    points: [ToneCurvePoint] = [
      ToneCurvePoint(x: 0, y: 0),
      ToneCurvePoint(x: 1, y: 1),
    ]
  ) {
    let normalized =
      points
      .sorted { $0.x < $1.x }
      .reduce(into: [ToneCurvePoint]()) { result, point in
        if result.last?.x == point.x {
          result[result.count - 1] = point
        } else {
          result.append(point)
        }
      }
    self.points =
      normalized.count >= 2
      ? normalized
      : [ToneCurvePoint(x: 0, y: 0), ToneCurvePoint(x: 1, y: 1)]
  }

  public func value(at input: Double) -> Double {
    let input = min(max(input, 0), 1)
    guard let first = points.first, let last = points.last else {
      return input
    }
    if input <= first.x { return first.y }
    if input >= last.x { return last.y }
    for (left, right) in zip(points, points.dropFirst())
    where input >= left.x && input <= right.x {
      let width = max(right.x - left.x, 0.000_001)
      let progress = (input - left.x) / width
      return left.y + (right.y - left.y) * progress
    }
    return input
  }

  public static let identity = ToneCurve()

  private enum CodingKeys: String, CodingKey {
    case points
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(points: try container.decode([ToneCurvePoint].self, forKey: .points))
  }
}

public enum HSLColorBand: String, Codable, CaseIterable, Sendable {
  case red
  case orange
  case yellow
  case green
  case aqua
  case blue
  case purple
  case magenta
}

public struct HSLBandAdjustment: Codable, Equatable, Sendable {
  public var hue: Double
  public var saturation: Double
  public var luminance: Double

  public init(
    hue: Double = 0,
    saturation: Double = 0,
    luminance: Double = 0
  ) {
    self.hue = min(max(hue, -1), 1)
    self.saturation = min(max(saturation, -1), 1)
    self.luminance = min(max(luminance, -1), 1)
  }

  public static let neutral = HSLBandAdjustment()

  private enum CodingKeys: String, CodingKey {
    case hue
    case saturation
    case luminance
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      hue: try container.decode(Double.self, forKey: .hue),
      saturation: try container.decode(Double.self, forKey: .saturation),
      luminance: try container.decode(Double.self, forKey: .luminance)
    )
  }
}

public struct LocalImageAdjustment: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public var name: String
  public var settings: ImageAdjustmentSettings
  public var maskStrokes: [MaskStroke]
  public var isVisible: Bool

  public init(
    id: UUID = UUID(),
    name: String,
    settings: ImageAdjustmentSettings = .neutral,
    maskStrokes: [MaskStroke] = [],
    isVisible: Bool = true
  ) {
    self.id = id
    self.name = name
    self.settings = settings
    self.maskStrokes = maskStrokes
    self.isVisible = isVisible
  }
}
