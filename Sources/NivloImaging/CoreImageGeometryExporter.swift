import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import NivloDomain
import UniformTypeIdentifiers

#if canImport(AppKit)
  import AppKit
#endif

public enum CoreImageGeometryExporterError: Error, LocalizedError, Sendable {
  case unreadableImage
  case renderFailed
  case writeFailed

  public var errorDescription: String? {
    switch self {
    case .unreadableImage:
      "The image could not be read."
    case .renderFailed:
      "The edited image could not be rendered."
    case .writeFailed:
      "The edited image could not be written."
    }
  }
}

public protocol EditedImageRendering: Sendable {
  func render(
    sourceURL: URL,
    outputURL: URL,
    snapshot: ImageEditSnapshot
  ) throws
}

public struct CoreImageGeometryExporter: Sendable, EditedImageRendering {
  public init() {}

  public func render(
    sourceURL: URL,
    outputURL: URL,
    snapshot: ImageEditSnapshot
  ) throws {
    try exportPNG(
      sourceURL: sourceURL,
      outputURL: outputURL,
      cropRect: snapshot.cropRect,
      quarterTurns: snapshot.quarterTurns,
      flippedHorizontally: snapshot.flippedHorizontally,
      adjustments: snapshot.adjustments,
      annotations: snapshot.annotations,
      maskStrokes: snapshot.maskStrokes,
      localAdjustments: snapshot.localAdjustments,
      layers: snapshot.layers
    )
  }

  public func exportPNG(
    sourceURL: URL,
    outputURL: URL,
    cropRect: NormalizedCropRect = .full,
    quarterTurns: Int = 0,
    flippedHorizontally: Bool = false,
    adjustments: ImageAdjustmentSettings = .neutral,
    annotations: [ImageAnnotation] = [],
    maskStrokes: [MaskStroke] = [],
    localAdjustments: [LocalImageAdjustment] = [],
    layers: [EditorLayer] = EditorLayer.defaults
  ) throws {
    guard var image = CIImage(contentsOf: sourceURL) else {
      throw CoreImageGeometryExporterError.unreadableImage
    }

    let center = CGPoint(x: image.extent.midX, y: image.extent.midY)
    var transform = CGAffineTransform(translationX: center.x, y: center.y)
    if flippedHorizontally {
      transform = transform.scaledBy(x: -1, y: 1)
    }
    let normalizedTurns = ((quarterTurns % 4) + 4) % 4
    transform = transform.rotated(by: CGFloat(normalizedTurns) * .pi / 2)
    transform = transform.translatedBy(x: -center.x, y: -center.y)
    image = image.transformed(by: transform)

    var extent = image.extent.integral
    image = image.transformed(
      by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
    )

    let orderedLayers = layers.isEmpty ? EditorLayer.defaults : layers
    for layer in orderedLayers where layer.isVisible {
      switch layer.kind {
      case .background:
        continue
      case .adjustments:
        image = applyAdjustments(adjustments, to: image)
      case .localAdjustments:
        image = applyLocalAdjustments(localAdjustments, to: image)
      case .mask:
        if !maskStrokes.isEmpty {
          image = applyMask(maskStrokes, to: image)
        }
      case .annotations:
        image = rasterizeAnnotations(annotations, over: image)
      }
    }

    if !cropRect.isEffectivelyFull {
      let cropCGRect = cropRect.ciCropCGRect(
        imageWidth: extent.width,
        imageHeight: extent.height
      )
      if cropCGRect.width > 0, cropCGRect.height > 0 {
        image = image.cropped(to: cropCGRect)
        image = image.transformed(
          by: CGAffineTransform(translationX: -cropCGRect.minX, y: -cropCGRect.minY)
        )
        extent = image.extent.integral
      }
    }

    let outputExtent = image.extent.integral
    let context = CIContext(options: [.useSoftwareRenderer: false])
    guard let cgImage = context.createCGImage(image, from: outputExtent) else {
      throw CoreImageGeometryExporterError.renderFailed
    }

    guard
      let destination = CGImageDestinationCreateWithURL(
        outputURL as CFURL,
        UTType.png.identifier as CFString,
        1,
        nil
      )
    else {
      throw CoreImageGeometryExporterError.writeFailed
    }
    CGImageDestinationAddImage(destination, cgImage, nil)
    guard CGImageDestinationFinalize(destination) else {
      throw CoreImageGeometryExporterError.writeFailed
    }
  }

  private func applyAdjustments(
    _ settings: ImageAdjustmentSettings,
    to image: CIImage
  ) -> CIImage {
    var output = image
    if settings.exposure != 0,
      let filter = CIFilter(name: "CIExposureAdjust")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.exposure, forKey: kCIInputEVKey)
      output = filter.outputImage ?? output
    }
    if settings.contrast != 0,
      let filter = CIFilter(name: "CIColorControls")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(1 + settings.contrast, forKey: kCIInputContrastKey)
      filter.setValue(1 + settings.saturation, forKey: kCIInputSaturationKey)
      output = filter.outputImage ?? output
    } else if settings.saturation != 0,
      let filter = CIFilter(name: "CIColorControls")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(1 + settings.saturation, forKey: kCIInputSaturationKey)
      output = filter.outputImage ?? output
    }
    if settings.warmth != 0,
      let filter = CIFilter(name: "CITemperatureAndTint")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(
        CIVector(
          x: 6_500 + settings.warmth * 1_500,
          y: settings.tint * 150
        ),
        forKey: "inputNeutral"
      )
      filter.setValue(CIVector(x: 6_500, y: 0), forKey: "inputTargetNeutral")
      output = filter.outputImage ?? output
    } else if settings.tint != 0,
      let filter = CIFilter(name: "CITemperatureAndTint")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(
        CIVector(x: 6_500, y: settings.tint * 150),
        forKey: "inputNeutral"
      )
      filter.setValue(CIVector(x: 6_500, y: 0), forKey: "inputTargetNeutral")
      output = filter.outputImage ?? output
    }
    if settings.highlights != 0 || settings.shadows != 0,
      let filter = CIFilter(name: "CIHighlightShadowAdjust")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.shadows, forKey: "inputShadowAmount")
      filter.setValue(1 + settings.highlights, forKey: "inputHighlightAmount")
      output = filter.outputImage ?? output
    }
    if settings.vibrance != 0,
      let filter = CIFilter(name: "CIVibrance")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.vibrance, forKey: "inputAmount")
      output = filter.outputImage ?? output
    }
    output = applyColorMapping(settings, to: output)
    if settings.clarity > 0,
      let filter = CIFilter(name: "CIUnsharpMask")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(1.5 + settings.clarity * 3, forKey: kCIInputRadiusKey)
      filter.setValue(settings.clarity * 1.5, forKey: kCIInputIntensityKey)
      output = filter.outputImage ?? output
    } else if settings.clarity < 0,
      let filter = CIFilter(name: "CIGaussianBlur")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(abs(settings.clarity) * 2, forKey: kCIInputRadiusKey)
      output = (filter.outputImage ?? output).cropped(to: output.extent)
    }
    if settings.sharpness > 0,
      let filter = CIFilter(name: "CISharpenLuminance")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.sharpness * 1.5, forKey: kCIInputSharpnessKey)
      filter.setValue(1 + settings.sharpness * 2, forKey: kCIInputRadiusKey)
      output = filter.outputImage ?? output
    }
    if settings.noiseReduction > 0,
      let filter = CIFilter(name: "CINoiseReduction")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.noiseReduction * 0.08, forKey: "inputNoiseLevel")
      filter.setValue(settings.noiseReduction * 0.6, forKey: "inputSharpness")
      output = filter.outputImage ?? output
    }
    if settings.vignette > 0,
      let filter = CIFilter(name: "CIVignette")
    {
      filter.setValue(output, forKey: kCIInputImageKey)
      filter.setValue(settings.vignette * 2, forKey: kCIInputIntensityKey)
      filter.setValue(
        min(output.extent.width, output.extent.height) * 0.45,
        forKey: kCIInputRadiusKey
      )
      output = filter.outputImage ?? output
    }
    return output
  }

  private func applyLocalAdjustments(
    _ adjustments: [LocalImageAdjustment],
    to image: CIImage
  ) -> CIImage {
    adjustments.reduce(image) { current, adjustment in
      guard
        adjustment.isVisible,
        !adjustment.maskStrokes.isEmpty,
        let mask = maskImage(
          adjustment.maskStrokes,
          extent: current.extent.integral
        ),
        let blend = CIFilter(name: "CIBlendWithMask")
      else {
        return current
      }
      blend.setValue(
        applyAdjustments(adjustment.settings, to: current),
        forKey: kCIInputImageKey
      )
      blend.setValue(current, forKey: kCIInputBackgroundImageKey)
      blend.setValue(mask, forKey: kCIInputMaskImageKey)
      return blend.outputImage ?? current
    }
  }

  private func applyColorMapping(
    _ settings: ImageAdjustmentSettings,
    to image: CIImage
  ) -> CIImage {
    guard
      !settings.levels.isEmpty
        || !settings.curves.isEmpty
        || settings.colorBands.values.contains(where: { $0 != .neutral })
    else {
      return image
    }
    let dimension = 32
    var cube = [Float]()
    cube.reserveCapacity(dimension * dimension * dimension * 4)
    for blueIndex in 0..<dimension {
      for greenIndex in 0..<dimension {
        for redIndex in 0..<dimension {
          var red = Double(redIndex) / Double(dimension - 1)
          var green = Double(greenIndex) / Double(dimension - 1)
          var blue = Double(blueIndex) / Double(dimension - 1)
          red = mapChannel(red, channel: .red, settings: settings)
          green = mapChannel(green, channel: .green, settings: settings)
          blue = mapChannel(blue, channel: .blue, settings: settings)
          (red, green, blue) = applyColorBands(
            red: red,
            green: green,
            blue: blue,
            adjustments: settings.colorBands
          )
          cube.append(Float(red))
          cube.append(Float(green))
          cube.append(Float(blue))
          cube.append(1)
        }
      }
    }
    let data = cube.withUnsafeBytes { Data($0) }
    guard let filter = CIFilter(name: "CIColorCube") else {
      return image
    }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(dimension, forKey: "inputCubeDimension")
    filter.setValue(data, forKey: "inputCubeData")
    return filter.outputImage ?? image
  }

  private func mapChannel(
    _ input: Double,
    channel: ImageColorChannel,
    settings: ImageAdjustmentSettings
  ) -> Double {
    var output = applyLevels(
      input,
      levels: settings.levels[.rgb] ?? .neutral
    )
    output = applyLevels(
      output,
      levels: settings.levels[channel] ?? .neutral
    )
    output = (settings.curves[channel] ?? .identity).value(at: output)
    output = (settings.curves[.rgb] ?? .identity).value(at: output)
    return min(max(output, 0), 1)
  }

  private func applyLevels(_ input: Double, levels: ImageLevels) -> Double {
    let normalized = min(
      max((input - levels.blackPoint) / (levels.whitePoint - levels.blackPoint), 0),
      1
    )
    return pow(normalized, 1 / levels.gamma)
  }

  private func applyColorBands(
    red: Double,
    green: Double,
    blue: Double,
    adjustments: [HSLColorBand: HSLBandAdjustment]
  ) -> (Double, Double, Double) {
    var hsv = rgbToHSV(red: red, green: green, blue: blue)
    for (band, adjustment) in adjustments where adjustment != .neutral {
      let distance = circularHueDistance(hsv.hue, hueCenter(for: band))
      let weight = max(0, 1 - distance / 0.14)
      guard weight > 0 else { continue }
      hsv.hue = normalizedHue(hsv.hue + adjustment.hue * 0.08 * weight)
      hsv.saturation = min(
        max(hsv.saturation + adjustment.saturation * weight, 0),
        1
      )
      hsv.value = min(max(hsv.value + adjustment.luminance * weight, 0), 1)
    }
    return hsvToRGB(
      hue: hsv.hue,
      saturation: hsv.saturation,
      value: hsv.value
    )
  }

  private func rgbToHSV(
    red: Double,
    green: Double,
    blue: Double
  ) -> (hue: Double, saturation: Double, value: Double) {
    let maximum = max(red, green, blue)
    let minimum = min(red, green, blue)
    let delta = maximum - minimum
    let hue: Double
    if delta == 0 {
      hue = 0
    } else if maximum == red {
      hue = normalizedHue((green - blue) / delta / 6)
    } else if maximum == green {
      hue = normalizedHue(((blue - red) / delta + 2) / 6)
    } else {
      hue = normalizedHue(((red - green) / delta + 4) / 6)
    }
    return (
      hue,
      maximum == 0 ? 0 : delta / maximum,
      maximum
    )
  }

  private func hsvToRGB(
    hue: Double,
    saturation: Double,
    value: Double
  ) -> (Double, Double, Double) {
    let sector = normalizedHue(hue) * 6
    let index = Int(floor(sector)) % 6
    let fraction = sector - floor(sector)
    let p = value * (1 - saturation)
    let q = value * (1 - fraction * saturation)
    let t = value * (1 - (1 - fraction) * saturation)
    switch index {
    case 0: return (value, t, p)
    case 1: return (q, value, p)
    case 2: return (p, value, t)
    case 3: return (p, q, value)
    case 4: return (t, p, value)
    default: return (value, p, q)
    }
  }

  private func normalizedHue(_ value: Double) -> Double {
    let remainder = value.truncatingRemainder(dividingBy: 1)
    return remainder < 0 ? remainder + 1 : remainder
  }

  private func circularHueDistance(_ left: Double, _ right: Double) -> Double {
    let distance = abs(left - right)
    return min(distance, 1 - distance)
  }

  private func hueCenter(for band: HSLColorBand) -> Double {
    switch band {
    case .red: 0
    case .orange: 1 / 12
    case .yellow: 1 / 6
    case .green: 1 / 3
    case .aqua: 1 / 2
    case .blue: 2 / 3
    case .purple: 3 / 4
    case .magenta: 11 / 12
    }
  }

  private func rasterizeAnnotations(
    _ annotations: [ImageAnnotation],
    over image: CIImage
  ) -> CIImage {
    #if !canImport(AppKit)
      return image
    #else
      guard !annotations.isEmpty else {
        return image
      }
      let extent = image.extent.integral
      guard
        let baseImage = CIContext().createCGImage(image, from: extent),
        let context = CGContext(
          data: nil,
          width: Int(extent.width),
          height: Int(extent.height),
          bitsPerComponent: 8,
          bytesPerRow: Int(extent.width) * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else {
        return image
      }
      context.draw(baseImage, in: CGRect(origin: .zero, size: extent.size))
      NSGraphicsContext.saveGraphicsState()
      NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
      defer {
        NSGraphicsContext.restoreGraphicsState()
      }

      for annotation in annotations {
        let pixel = annotation.normalizedRect.pixelRect(
          imageWidth: Int(extent.width),
          imageHeight: Int(extent.height)
        )
        let rect = CGRect(
          x: CGFloat(pixel.x),
          y: extent.height - CGFloat(pixel.y) - CGFloat(pixel.height),
          width: CGFloat(pixel.width),
          height: CGFloat(pixel.height)
        )
        context.saveGState()
        if annotation.kind != .arrow, annotation.rotationDegrees != 0 {
          context.translateBy(x: rect.midX, y: rect.midY)
          context.rotate(by: CGFloat(-annotation.rotationDegrees * .pi / 180))
          context.translateBy(x: -rect.midX, y: -rect.midY)
        }
        switch annotation.kind {
        case .rectangle:
          context.setFillColor(nsColor(annotation.rectangleStyle.fillColor).cgColor)
          context.fill(rect)
          context.setStrokeColor(nsColor(annotation.rectangleStyle.strokeColor).cgColor)
          context.setLineWidth(annotation.rectangleStyle.lineWidth)
          context.setLineDash(
            phase: 0,
            lengths: dashPattern(annotation.rectangleStyle.lineStyle)
          )
          context.stroke(rect)
          context.setLineDash(phase: 0, lengths: [])
        case .arrow:
          drawArrow(
            start: annotation.arrowStart,
            end: annotation.arrowEnd,
            extent: extent,
            style: annotation.arrowStyle,
            context: context
          )
        case .text:
          var font =
            NSFont(
              name: annotation.textStyle.fontName,
              size: annotation.textStyle.fontSize
            ) ?? NSFont.systemFont(ofSize: annotation.textStyle.fontSize)
          if annotation.textStyle.isBold {
            font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
          }
          if annotation.textStyle.isItalic {
            font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
          }
          let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: nsColor(annotation.textStyle.color),
          ]
          let text = annotation.text.isEmpty ? "Text" : annotation.text
          text.draw(
            with: rect,
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            attributes: attributes
          )
        }
        context.restoreGState()
      }

      guard let annotated = context.makeImage() else {
        return image
      }
      return CIImage(cgImage: annotated)
    #endif
  }

  private func applyMask(_ strokes: [MaskStroke], to image: CIImage) -> CIImage {
    #if !canImport(AppKit)
      return image
    #else
      guard
        let maskImage = maskImage(strokes, extent: image.extent.integral),
        let filter = CIFilter(name: "CIBlendWithMask")
      else {
        return image
      }
      filter.setValue(image, forKey: kCIInputImageKey)
      filter.setValue(
        CIImage(color: .clear).cropped(to: image.extent),
        forKey: kCIInputBackgroundImageKey
      )
      filter.setValue(maskImage, forKey: kCIInputMaskImageKey)
      return filter.outputImage ?? image
    #endif
  }

  private func maskImage(
    _ strokes: [MaskStroke],
    extent: CGRect
  ) -> CIImage? {
    #if !canImport(AppKit)
      return nil
    #else
      guard
        let maskContext = CGContext(
          data: nil,
          width: Int(extent.width),
          height: Int(extent.height),
          bitsPerComponent: 8,
          bytesPerRow: Int(extent.width) * 4,
          space: CGColorSpaceCreateDeviceRGB(),
          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
      else {
        return nil
      }
      maskContext.setFillColor(CGColor(gray: 0, alpha: 1))
      maskContext.fill(CGRect(origin: .zero, size: extent.size))
      let minDimension = min(extent.width, extent.height)
      for stroke in strokes where !stroke.points.isEmpty {
        let component: CGFloat = stroke.operation == .paint ? 1 : 0
        let strokeColor = CGColor(gray: component, alpha: 1)
        maskContext.setFillColor(strokeColor)
        maskContext.setStrokeColor(strokeColor)
        let radius = max(4, CGFloat(stroke.brushRadius) * minDimension)
        maskContext.setLineWidth(radius * 2)
        maskContext.setLineCap(.round)
        maskContext.setLineJoin(.round)
        maskContext.beginPath()
        for (index, point) in stroke.points.enumerated() {
          let pixel = CGPoint(
            x: CGFloat(point.x) * extent.width,
            y: CGFloat(1 - point.y) * extent.height
          )
          if index == 0 {
            maskContext.move(to: pixel)
          } else {
            maskContext.addLine(to: pixel)
          }
        }
        if stroke.points.count == 1, let point = stroke.points.first {
          let pixelX = CGFloat(point.x) * extent.width
          let pixelY = CGFloat(1 - point.y) * extent.height
          maskContext.fillEllipse(
            in: CGRect(
              x: pixelX - radius,
              y: pixelY - radius,
              width: radius * 2,
              height: radius * 2
            )
          )
        } else {
          maskContext.strokePath()
        }
      }
      guard let image = maskContext.makeImage() else { return nil }
      return CIImage(cgImage: image)
    #endif
  }

  #if canImport(AppKit)
    private func nsColor(_ color: RGBAColor) -> NSColor {
      NSColor(
        red: color.red,
        green: color.green,
        blue: color.blue,
        alpha: color.alpha
      )
    }

    private func dashPattern(_ style: AnnotationLineStyle) -> [CGFloat] {
      switch style {
      case .solid:
        []
      case .dashed:
        [12, 8]
      case .dashDot:
        [12, 6, 2, 6]
      }
    }

    private func drawArrow(
      start: NormalizedPoint,
      end: NormalizedPoint,
      extent: CGRect,
      style: ArrowAnnotationStyle,
      context: CGContext?
    ) {
      guard let context else { return }
      let start = CGPoint(
        x: start.x * extent.width,
        y: (1 - start.y) * extent.height
      )
      let end = CGPoint(
        x: end.x * extent.width,
        y: (1 - end.y) * extent.height
      )
      context.setStrokeColor(nsColor(style.color).cgColor)
      context.setLineWidth(style.lineWidth)
      context.setLineCap(.round)
      context.setLineJoin(.round)
      context.move(to: start)
      context.addLine(to: end)
      if style.direction == .forward || style.direction == .both {
        addArrowHead(context: context, tip: end, from: start, lineWidth: style.lineWidth)
      }
      if style.direction == .backward || style.direction == .both {
        addArrowHead(context: context, tip: start, from: end, lineWidth: style.lineWidth)
      }
      context.strokePath()
    }

    private func addArrowHead(
      context: CGContext,
      tip: CGPoint,
      from: CGPoint,
      lineWidth: Double
    ) {
      let angle = atan2(tip.y - from.y, tip.x - from.x)
      let distance = hypot(tip.x - from.x, tip.y - from.y)
      let length = max(CGFloat(lineWidth) * 4, min(36, distance * 0.18))
      for offset in [CGFloat.pi * 0.78, -CGFloat.pi * 0.78] {
        context.move(to: tip)
        context.addLine(
          to: CGPoint(
            x: tip.x + cos(angle + offset) * length,
            y: tip.y + sin(angle + offset) * length
          )
        )
      }
    }
  #endif
}
