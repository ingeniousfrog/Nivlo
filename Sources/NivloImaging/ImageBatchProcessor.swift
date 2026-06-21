import Foundation
import ImageIO
import NivloDomain
import UniformTypeIdentifiers

public enum ImageBatchProcessorError: Error, LocalizedError, Equatable, Sendable {
  case unreadableImage(URL)
  case unsupportedFormat(String)
  case writeFailed(URL)

  public var errorDescription: String? {
    switch self {
    case .unreadableImage(let url):
      "Could not read image at \(url.path)."
    case .unsupportedFormat(let format):
      "This macOS installation cannot write \(format) images."
    case .writeFailed(let url):
      "Could not write processed image to \(url.path)."
    }
  }
}

public enum ImageOutputFormat: String, Sendable {
  case png
  case jpeg
  case webp
  case avif

  var fileExtension: String {
    switch self {
    case .png:
      "png"
    case .jpeg:
      "jpg"
    case .webp:
      "webp"
    case .avif:
      "avif"
    }
  }

  var typeIdentifier: String {
    switch self {
    case .png:
      UTType.png.identifier
    case .jpeg:
      UTType.jpeg.identifier
    case .webp:
      "org.webmproject.webp"
    case .avif:
      "public.avif"
    }
  }
}

public struct ImageBatchRequest: Sendable {
  public let assets: [ImageAsset]
  public let outputDirectory: URL
  public let format: ImageOutputFormat
  public let compressionQuality: Double?
  public let maxPixelSize: Int?
  public let filenameTemplate: String?

  public init(
    assets: [ImageAsset],
    outputDirectory: URL,
    format: ImageOutputFormat,
    compressionQuality: Double? = nil,
    maxPixelSize: Int? = nil,
    filenameTemplate: String? = nil
  ) {
    self.assets = assets
    self.outputDirectory = outputDirectory.standardizedFileURL
    self.format = format
    self.compressionQuality = compressionQuality
    self.maxPixelSize = maxPixelSize
    self.filenameTemplate = filenameTemplate
  }
}

public struct ProcessedImageAsset: Equatable, Sendable {
  public let sourceAssetID: AssetID
  public let url: URL
}

public struct ImageBatchProcessor: Sendable {
  public init() {}

  public func process(
    _ request: ImageBatchRequest
  ) async throws -> [ProcessedImageAsset] {
    try FileManager.default.createDirectory(
      at: request.outputDirectory,
      withIntermediateDirectories: true
    )

    var outputs: [ProcessedImageAsset] = []
    for (index, asset) in request.assets.enumerated() {
      let image = try renderImage(for: asset, maxPixelSize: request.maxPixelSize)
      let outputURL = uniqueOutputURL(
        asset: asset,
        index: index + 1,
        request: request
      )
      try write(
        image,
        to: outputURL,
        format: request.format,
        compressionQuality: request.compressionQuality
      )
      outputs.append(
        ProcessedImageAsset(sourceAssetID: asset.id, url: outputURL)
      )
    }
    return outputs
  }

  private func renderImage(
    for asset: ImageAsset,
    maxPixelSize: Int?
  ) throws -> CGImage {
    guard let source = CGImageSourceCreateWithURL(asset.url as CFURL, nil) else {
      throw ImageBatchProcessorError.unreadableImage(asset.url)
    }
    if let maxPixelSize {
      let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
        kCGImageSourceCreateThumbnailWithTransform: true,
      ]
      guard
        let image = CGImageSourceCreateThumbnailAtIndex(
          source,
          0,
          options as CFDictionary
        )
      else {
        throw ImageBatchProcessorError.unreadableImage(asset.url)
      }
      return image
    }
    guard let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
      throw ImageBatchProcessorError.unreadableImage(asset.url)
    }
    return image
  }

  private func write(
    _ image: CGImage,
    to url: URL,
    format: ImageOutputFormat,
    compressionQuality: Double?
  ) throws {
    guard
      let destination = CGImageDestinationCreateWithURL(
        url as CFURL,
        format.typeIdentifier as CFString,
        1,
        nil
      )
    else {
      throw ImageBatchProcessorError.unsupportedFormat(format.rawValue)
    }
    var properties: [CFString: Any] = [:]
    if let compressionQuality {
      properties[kCGImageDestinationLossyCompressionQuality] =
        min(1, max(0, compressionQuality))
    }
    CGImageDestinationAddImage(
      destination,
      image,
      properties.isEmpty ? nil : properties as CFDictionary
    )
    guard CGImageDestinationFinalize(destination) else {
      try? FileManager.default.removeItem(at: url)
      throw ImageBatchProcessorError.writeFailed(url)
    }
  }

  private func uniqueOutputURL(
    asset: ImageAsset,
    index: Int,
    request: ImageBatchRequest
  ) -> URL {
    let baseName = outputBaseName(
      asset: asset,
      index: index,
      template: request.filenameTemplate
    )
    let candidate = request.outputDirectory
      .appending(path: "\(baseName).\(request.format.fileExtension)")
    guard FileManager.default.fileExists(atPath: candidate.path) else {
      return candidate
    }

    var suffix = 1
    while true {
      let url = request.outputDirectory
        .appending(path: "\(baseName)-\(suffix).\(request.format.fileExtension)")
      if !FileManager.default.fileExists(atPath: url.path) {
        return url
      }
      suffix += 1
    }
  }

  private func outputBaseName(
    asset: ImageAsset,
    index: Int,
    template: String?
  ) -> String {
    guard let template, !template.isEmpty else {
      return asset.url.deletingPathExtension().lastPathComponent
    }
    return sanitizeFilename(
      template
        .replacingOccurrences(of: "{index}", with: "\(index)")
        .replacingOccurrences(
          of: "{name}",
          with: asset.url.deletingPathExtension().lastPathComponent
        )
    )
  }

  private func sanitizeFilename(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/:")
      .union(.newlines)
      .union(.controlCharacters)
    let components = value.components(separatedBy: invalid)
      .filter { !$0.isEmpty }
    let sanitized = components.joined(separator: "-")
      .trimmingCharacters(in: .whitespacesAndNewlines)
    return sanitized.isEmpty ? "image" : sanitized
  }
}
