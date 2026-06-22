import Foundation

public struct AssetPreviewDetails: Equatable, Sendable {
  public let title: String
  public let format: String
  public let dimensions: String
  public let fileSize: String
  public let path: String

  public init(asset: ImageAsset) {
    title = asset.filename
    format = Self.formatTitle(for: asset.contentType)
    dimensions = Self.dimensionsTitle(width: asset.pixelWidth, height: asset.pixelHeight)
    fileSize = Self.fileSizeTitle(asset.fileSize)
    path = asset.url.standardizedFileURL.path
  }

  private static func formatTitle(for contentType: String) -> String {
    let suffix = contentType.components(separatedBy: ".").last ?? "image"
    return suffix.uppercased()
  }

  private static func dimensionsTitle(width: Int?, height: Int?) -> String {
    guard let width, let height else {
      return "Unknown"
    }
    return "\(width) × \(height)"
  }

  private static func fileSizeTitle(_ byteCount: Int64) -> String {
    ByteCountFormatter.string(
      fromByteCount: byteCount,
      countStyle: .file
    )
  }
}
