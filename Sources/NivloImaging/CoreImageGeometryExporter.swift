#if canImport(AppKit)
  import AppKit
#endif
import CoreGraphics
import CoreImage
import Foundation
import ImageIO
import NivloDomain
import UniformTypeIdentifiers

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

public struct CoreImageGeometryExporter: Sendable {
  public init() {}

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

    let pixelCrop = cropRect.pixelRect(
      imageWidth: Int(image.extent.width.rounded()),
      imageHeight: Int(image.extent.height.rounded())
    )
    let cropCGRect = CGRect(
      x: pixelCrop.x,
      y: pixelCrop.y,
      width: pixelCrop.width,
      height: pixelCrop.height
    )
    if cropCGRect.width > 0, cropCGRect.height > 0 {
      image = image.cropped(to: cropCGRect)
      image = image.transformed(
        by: CGAffineTransform(translationX: -cropCGRect.minX, y: -cropCGRect.minY)
      )
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

    let extent = image.extent.integral
    image = image.transformed(
      by: CGAffineTransform(translationX: -extent.minX, y: -extent.minY)
    )
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
      let rect = CGRect(x: pixel.x, y: pixel.y, width: pixel.width, height: pixel.height)
      switch annotation.kind {
      case .rectangle:
        context?.setStrokeColor(NSColor.systemYellow.cgColor)
        context?.setLineWidth(3)
        context?.stroke(rect)
      case .arrow:
        context?.setStrokeColor(NSColor.systemOrange.cgColor)
        context?.setLineWidth(3)
        context?.move(to: CGPoint(x: rect.minX, y: rect.minY))
        context?.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        context?.strokePath()
      case .text:
        let attributes: [NSAttributedString.Key: Any] = [
          .font: NSFont.systemFont(ofSize: 18, weight: .semibold),
          .foregroundColor: NSColor.white,
        ]
        let text = annotation.text.isEmpty ? "Note" : annotation.text
        text.draw(at: rect.origin, withAttributes: attributes)
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
    let maskImage = NSImage(size: extent.size)
    maskImage.lockFocus()
    defer { maskImage.unlockFocus() }
    NSColor.black.setFill()
    NSBezierPath(rect: CGRect(origin: .zero, size: extent.size)).fill()
    NSColor.white.setFill()
    for stroke in strokes {
      let pixel = stroke.normalizedRect.pixelRect(
        imageWidth: Int(extent.width),
        imageHeight: Int(extent.height)
      )
      NSBezierPath(
        ovalIn: CGRect(x: pixel.x, y: pixel.y, width: pixel.width, height: pixel.height)
      ).fill()
    }
    guard
      let maskCGImage = maskImage.cgImage(forProposedRect: nil, context: nil, hints: nil),
      let filter = CIFilter(name: "CIBlendWithMask")
    else {
      return image
    }
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(CIImage(color: .clear).cropped(to: extent), forKey: kCIInputBackgroundImageKey)
    filter.setValue(CIImage(cgImage: maskCGImage), forKey: kCIInputMaskImageKey)
    return filter.outputImage ?? image
    #endif
  }
}
