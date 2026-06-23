import CoreGraphics
import Foundation
import ImageIO

public struct ImageHistogramChannel: Equatable, Sendable {
  public let bins: [Int]

  public init(bins: [Int]) {
    self.bins =
      bins.count == 256
      ? bins
      : Array(bins.prefix(256))
        + Array(repeating: 0, count: max(0, 256 - bins.count))
  }

  public var totalCount: Int {
    bins.reduce(0, +)
  }
}

public struct ImageHistogram: Equatable, Sendable {
  public let red: ImageHistogramChannel
  public let green: ImageHistogramChannel
  public let blue: ImageHistogramChannel
  public let luminance: ImageHistogramChannel

  public init(
    red: ImageHistogramChannel,
    green: ImageHistogramChannel,
    blue: ImageHistogramChannel,
    luminance: ImageHistogramChannel
  ) {
    self.red = red
    self.green = green
    self.blue = blue
    self.luminance = luminance
  }

  public var shadowClippingCount: Int {
    luminance.bins.prefix(2).reduce(0, +)
  }

  public var highlightClippingCount: Int {
    luminance.bins.suffix(2).reduce(0, +)
  }
}

public enum ImageHistogramAnalyzerError: Error, LocalizedError, Sendable {
  case unreadableImage
  case pixelBufferCreationFailed

  public var errorDescription: String? {
    switch self {
    case .unreadableImage:
      "The image could not be read for histogram analysis."
    case .pixelBufferCreationFailed:
      "The image pixels could not be prepared for histogram analysis."
    }
  }
}

public struct ImageHistogramAnalyzer: Sendable {
  public init() {}

  public func analyze(
    url: URL,
    maximumDimension: Int = 1_024
  ) throws -> ImageHistogram {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let image = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: max(1, maximumDimension),
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
      )
    else {
      throw ImageHistogramAnalyzerError.unreadableImage
    }

    let bytesPerRow = image.width * 4
    var pixels = [UInt8](repeating: 0, count: bytesPerRow * image.height)
    guard
      let context = CGContext(
        data: &pixels,
        width: image.width,
        height: image.height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw ImageHistogramAnalyzerError.pixelBufferCreationFailed
    }
    context.draw(
      image,
      in: CGRect(x: 0, y: 0, width: image.width, height: image.height)
    )

    var red = [Int](repeating: 0, count: 256)
    var green = [Int](repeating: 0, count: 256)
    var blue = [Int](repeating: 0, count: 256)
    var luminance = [Int](repeating: 0, count: 256)
    for offset in stride(from: 0, to: pixels.count, by: 4) {
      let redValue = Int(pixels[offset])
      let greenValue = Int(pixels[offset + 1])
      let blueValue = Int(pixels[offset + 2])
      let luminanceValue = min(
        255,
        max(
          0,
          Int(
            (0.2126 * Double(redValue)
              + 0.7152 * Double(greenValue)
              + 0.0722 * Double(blueValue)).rounded()
          )
        )
      )
      red[redValue] += 1
      green[greenValue] += 1
      blue[blueValue] += 1
      luminance[luminanceValue] += 1
    }

    return ImageHistogram(
      red: ImageHistogramChannel(bins: red),
      green: ImageHistogramChannel(bins: green),
      blue: ImageHistogramChannel(bins: blue),
      luminance: ImageHistogramChannel(bins: luminance)
    )
  }
}
