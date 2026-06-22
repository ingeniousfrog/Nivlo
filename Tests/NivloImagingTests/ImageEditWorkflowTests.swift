import CoreGraphics
import Foundation
import ImageIO
import NivloDomain
import Testing
import UniformTypeIdentifiers

@testable import NivloImaging

#if canImport(AppKit)
  import AppKit
#endif

@Suite("Image edit workflow")
struct ImageEditWorkflowTests {
  @Test("preview renderer creates its temporary directory")
  func previewCreatesTemporaryDirectory() throws {
    let fixture = try ImageEditWorkflowFixture(width: 120, height: 80)
    let previewDirectory = fixture.rootURL
      .appending(path: "missing", directoryHint: .isDirectory)
      .appending(path: "preview", directoryHint: .isDirectory)
    let renderer = ImageEditPreviewRenderer(tempDirectory: previewDirectory)

    let data = try renderer.renderPreview(
      sourceURL: fixture.imageURL,
      snapshot: ImageEditSnapshot(
        cropRect: NormalizedCropRect(x: 0, y: 0, width: 0.5, height: 1)
      )
    )

    #expect(!data.isEmpty)
    #expect(FileManager.default.fileExists(atPath: previewDirectory.path))
  }

  @Test("preview renders geometry adjustments annotations and masks together")
  func previewRendersCombinedEdits() throws {
    let fixture = try ImageEditWorkflowFixture(width: 120, height: 80)
    let renderer = ImageEditPreviewRenderer(
      tempDirectory: fixture.rootURL.appending(path: "combined-preview")
    )
    let snapshot = ImageEditSnapshot(
      cropRect: NormalizedCropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
      quarterTurns: 1,
      flippedHorizontally: true,
      adjustments: ImageAdjustmentSettings(
        exposure: 0.2,
        contrast: 0.1,
        saturation: 0.15,
        warmth: 0.1
      ),
      annotations: [
        ImageAnnotation(
          kind: .rectangle,
          normalizedRect: NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)
        )
      ],
      maskStrokes: [
        MaskStroke(
          points: [
            MaskBrushPoint(x: 0.25, y: 0.25),
            MaskBrushPoint(x: 0.75, y: 0.75),
          ],
          brushRadius: 0.2
        )
      ]
    )

    let data = try renderer.renderPreview(
      sourceURL: fixture.imageURL,
      snapshot: snapshot
    )
    let previewURL = fixture.rootURL.appending(path: "combined.png")
    try data.write(to: previewURL)
    let dimensions = try workflowImageDimensions(at: previewURL)

    #expect(dimensions == ImageDimensions(width: 64, height: 96))
  }

  #if canImport(AppKit)
    @Test("preview renderer produces an AppKit image")
    func previewProducesAppKitImage() throws {
      let fixture = try ImageEditWorkflowFixture(width: 120, height: 80)
      let renderer = ImageEditPreviewRenderer(
        tempDirectory: fixture.rootURL.appending(path: "appkit-preview")
      )

      let image = try renderer.renderPreviewImage(
        sourceURL: fixture.imageURL,
        snapshot: ImageEditSnapshot()
      )

      #expect(image.size.width == 120)
      #expect(image.size.height == 80)
    }

    @Test("preview renderer reports invalid rendered image data")
    func previewRejectsInvalidImageData() throws {
      let fixture = try ImageEditWorkflowFixture(width: 120, height: 80)
      let renderer = ImageEditPreviewRenderer(
        renderer: InvalidImageDataRenderer(),
        tempDirectory: fixture.rootURL.appending(path: "invalid-preview")
      )

      #expect(throws: ImageEditPreviewRendererError.renderFailed) {
        try renderer.renderPreviewImage(
          sourceURL: fixture.imageURL,
          snapshot: ImageEditSnapshot()
        )
      }
    }
  #endif

  @Test("export optimizes the fully edited intermediate image")
  func exportUsesEditedIntermediateImage() async throws {
    let fixture = try ImageEditWorkflowFixture(width: 120, height: 80)
    let outputURL = fixture.rootURL.appending(path: "edited.png")
    let pipeline = ImageEditPipeline(optimizer: CopyingImageOptimizer())
    let request = ImageEditRequest(
      sourceURL: fixture.imageURL,
      outputURL: outputURL,
      cropRect: NormalizedCropRect(x: 0.25, y: 0.25, width: 0.5, height: 0.5),
      format: .png
    )

    let result = try await pipeline.export(request)
    let sourceDimensions = try workflowImageDimensions(at: fixture.imageURL)
    let outputDimensions = try workflowImageDimensions(at: result.outputURL)

    #expect(sourceDimensions == ImageDimensions(width: 120, height: 80))
    #expect(outputDimensions == ImageDimensions(width: 60, height: 40))
  }
}

private struct InvalidImageDataRenderer: EditedImageRendering {
  func render(
    sourceURL _: URL,
    outputURL: URL,
    snapshot _: ImageEditSnapshot
  ) throws {
    try Data("not an image".utf8).write(to: outputURL)
  }
}

private struct CopyingImageOptimizer: ImageOptimizing {
  func optimize(_ request: PicxOptimizeRequest) async throws -> PicxOptimizeResult {
    try FileManager.default.copyItem(at: request.sourceURL, to: request.outputURL)
    let size =
      try FileManager.default.attributesOfItem(atPath: request.outputURL.path)[.size]
      as? NSNumber
    return PicxOptimizeResult(
      sourceURL: request.sourceURL,
      outputURL: request.outputURL,
      originalSize: size?.int64Value ?? 0,
      outputSize: size?.int64Value ?? 0,
      savingsRatio: 0
    )
  }
}

private struct ImageEditWorkflowFixture {
  let rootURL: URL
  let imageURL: URL

  init(width: Int, height: Int) throws {
    rootURL = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    imageURL = rootURL.appending(path: "source.png")
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
    try writeWorkflowFixtureImage(at: imageURL, width: width, height: height)
  }
}

private struct ImageDimensions: Equatable {
  let width: Int
  let height: Int
}

private func writeWorkflowFixtureImage(
  at url: URL,
  width: Int,
  height: Int
) throws {
  guard
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw ImageEditWorkflowFixtureError.creationFailed
  }
  context.setFillColor(CGColor(red: 0.85, green: 0.3, blue: 0.15, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else {
    throw ImageEditWorkflowFixtureError.creationFailed
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw ImageEditWorkflowFixtureError.creationFailed
  }
}

private func workflowImageDimensions(at url: URL) throws -> ImageDimensions {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? Int,
    let height = properties[kCGImagePropertyPixelHeight] as? Int
  else {
    throw ImageEditWorkflowFixtureError.creationFailed
  }
  return ImageDimensions(width: width, height: height)
}

private enum ImageEditWorkflowFixtureError: Error {
  case creationFailed
}
