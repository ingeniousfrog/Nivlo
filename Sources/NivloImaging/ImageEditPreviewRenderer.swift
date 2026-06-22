import Foundation
import NivloDomain

#if canImport(AppKit)
  import AppKit
#endif

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
  private let renderer: any EditedImageRendering
  private let tempDirectory: URL

  public init(
    renderer: any EditedImageRendering = CoreImageGeometryExporter(),
    tempDirectory: URL = NivloToolsDirectory.tempDirectory()
  ) {
    self.renderer = renderer
    self.tempDirectory = tempDirectory
  }

  public func renderPreview(
    sourceURL: URL,
    snapshot: ImageEditSnapshot
  ) throws -> Data {
    try FileManager.default.createDirectory(
      at: tempDirectory,
      withIntermediateDirectories: true
    )
    let tempURL =
      tempDirectory
      .appending(path: "\(UUID().uuidString)-preview.png")
    defer { try? FileManager.default.removeItem(at: tempURL) }
    try renderer.render(
      sourceURL: sourceURL,
      outputURL: tempURL,
      snapshot: snapshot
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
