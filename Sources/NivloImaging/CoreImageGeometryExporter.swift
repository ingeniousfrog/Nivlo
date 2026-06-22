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
    image = applyAdjustments(
      adjustments,
      to: image,
      enabled: layers.first(where: { $0.kind == .adjustments })?.isVisible != false
    )
    if layers.first(where: { $0.kind == .annotations })?.isVisible != false {
      image = rasterizeAnnotations(annotations, over: image)
    }
    if layers.first(where: { $0.kind == .mask })?.isVisible != false, !maskStrokes.isEmpty {
      image = applyMask(maskStrokes, to: image)
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
    to image: CIImage,
    enabled: Bool
  ) -> CIImage {
    guard enabled else {
      return image
    }
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
        CIVector(x: 6_500 + settings.warmth * 1_500, y: 0),
        forKey: "inputNeutral"
      )
      filter.setValue(CIVector(x: 6_500, y: 0), forKey: "inputTargetNeutral")
      output = filter.outputImage ?? output
    }
    return output
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
      let extent = image.extent
      let renderer = NSImage(size: extent.size)
      renderer.lockFocus()
      defer { renderer.unlockFocus() }

      let context = NSGraphicsContext.current?.cgContext
      if let cgImage = CIContext().createCGImage(image, from: extent) {
        context?.draw(cgImage, in: CGRect(origin: .zero, size: extent.size))
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
        switch annotation.kind {
        case .rectangle:
          context?.setFillColor(nsColor(annotation.rectangleStyle.fillColor).cgColor)
          context?.fill(rect)
          context?.setStrokeColor(nsColor(annotation.rectangleStyle.strokeColor).cgColor)
          context?.setLineWidth(annotation.rectangleStyle.lineWidth)
          context?.setLineDash(
            phase: 0,
            lengths: dashPattern(annotation.rectangleStyle.lineStyle)
          )
          context?.stroke(rect)
          context?.setLineDash(phase: 0, lengths: [])
        case .arrow:
          drawArrow(
            in: rect,
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
      }

      guard
        let annotated = renderer.cgImage(forProposedRect: nil, context: nil, hints: nil)
      else {
        return image
      }
      return CIImage(cgImage: annotated)
    #endif
  }

  private func applyMask(_ strokes: [MaskStroke], to image: CIImage) -> CIImage {
    #if !canImport(AppKit)
      return image
    #else
      let extent = image.extent.integral
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
        return image
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
      guard
        let maskCGImage = maskContext.makeImage(),
        let filter = CIFilter(name: "CIBlendWithMask")
      else {
        return image
      }
      filter.setValue(image, forKey: kCIInputImageKey)
      filter.setValue(
        CIImage(color: .clear).cropped(to: extent), forKey: kCIInputBackgroundImageKey)
      filter.setValue(CIImage(cgImage: maskCGImage), forKey: kCIInputMaskImageKey)
      return filter.outputImage ?? image
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
      in rect: CGRect,
      style: ArrowAnnotationStyle,
      context: CGContext?
    ) {
      guard let context else { return }
      let start = CGPoint(x: rect.minX, y: rect.minY)
      let end = CGPoint(x: rect.maxX, y: rect.maxY)
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
