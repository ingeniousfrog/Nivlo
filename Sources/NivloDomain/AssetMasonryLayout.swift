import Foundation

extension ImageAsset {
  public var displayAspectRatio: Double {
    guard
      let pixelWidth,
      let pixelHeight,
      pixelWidth > 0,
      pixelHeight > 0
    else {
      return mediaKind == .video ? 16.0 / 9.0 : 4.0 / 3.0
    }
    return min(2, max(0.5, Double(pixelWidth) / Double(pixelHeight)))
  }
}

public enum AssetMasonryLayout {
  /// Relative height reserved for filename, metadata, and card padding below the thumbnail.
  public static let cardChromeHeightRatio = 0.34

  public static func columns(
    for assets: [ImageAsset],
    columnCount: Int
  ) -> [[ImageAsset]] {
    let count = max(1, columnCount)
    var columns = Array(repeating: [ImageAsset](), count: count)
    var estimatedHeights = Array(repeating: 0.0, count: count)

    for asset in assets {
      let targetIndex =
        estimatedHeights.indices.min {
          estimatedHeights[$0] < estimatedHeights[$1]
        } ?? 0
      columns[targetIndex].append(asset)
      estimatedHeights[targetIndex] +=
        (1 / asset.displayAspectRatio) + cardChromeHeightRatio
    }
    return columns
  }
}
