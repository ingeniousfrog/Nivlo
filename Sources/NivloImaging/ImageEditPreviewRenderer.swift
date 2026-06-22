#if canImport(AppKit)
  import AppKit
#endif
import Foundation
import NivloDomain

public enum ImageEditPreviewRendererError: Error, LocalizedError, Sendable {
  case renderFailed

  public var errorDescription: String? {
    switch self {
    case .renderFailed:
      "The edit preview could not be rendered."
    }
  }
}

public struct ImageEditPreviewRenderer: Sendable {
  private let exporter = CoreImageGeometryExporter()

  public init() {}

  public func renderPreview(
    sourceURL: URL,
    snapshot: ImageEditSnapshot
  ) throws -> Data {
    let tempURL = NivloToolsDirectory.tempDirectory()
      .appending(path: "\(UUID().uuidString)-preview.png")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try exporter.exportPNG(
      sourceURL: sourceURL,
      outputURL: tempURL,
      cropRect: snapshot.cropRect,
      quarterTurns: snapshot.quarterTurns,
      flippedHorizontally: snapshot.flippedHorizontally,
      adjustments: snapshot.adjustments,
      annotations: snapshot.annotations,
      maskStrokes: snapshot.maskStrokes,
      layers: snapshot.layers
    )
    return try Data(contentsOf: tempURL)
  }
}

#if canImport(AppKit)
  extension ImageEditPreviewRenderer {
    public func renderPreviewImage(
      sourceURL: URL,
      snapshot: ImageEditSnapshot
    ) throws -> NSImage {
      let data = try renderPreview(sourceURL: sourceURL, snapshot: snapshot)
      guard let image = NSImage(data: data) else {
        throw ImageEditPreviewRendererError.renderFailed
      }
      return image
    }
  }
#endif
