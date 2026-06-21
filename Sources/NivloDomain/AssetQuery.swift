import Foundation

public struct AssetQuery: Equatable, Sendable {
  public let searchText: String
  public let folders: [URL]
  public let contentTypes: Set<String>
  public let minimumFileSize: Int64?
  public let maximumFileSize: Int64?
  public let minimumPixelWidth: Int?
  public let minimumPixelHeight: Int?
  public let colors: Set<String>
  public let keywords: Set<String>

  public init(
    searchText: String = "",
    folders: [URL] = [],
    contentTypes: Set<String> = [],
    minimumFileSize: Int64? = nil,
    maximumFileSize: Int64? = nil,
    minimumPixelWidth: Int? = nil,
    minimumPixelHeight: Int? = nil,
    colors: Set<String> = [],
    keywords: Set<String> = []
  ) {
    self.searchText = searchText
    self.folders = folders.map(\.standardizedFileURL)
    self.contentTypes = contentTypes
    self.minimumFileSize = minimumFileSize
    self.maximumFileSize = maximumFileSize
    self.minimumPixelWidth = minimumPixelWidth
    self.minimumPixelHeight = minimumPixelHeight
    self.colors = Set(colors.map { $0.lowercased() })
    self.keywords = Set(keywords.map { $0.lowercased() })
  }

  public func apply(
    to assets: [ImageAsset],
    enrichments: [AssetID: AssetEnrichment]
  ) -> [ImageAsset] {
    let tokens =
      searchText
      .split(whereSeparator: \.isWhitespace)
      .map { String($0).lowercased() }
    return assets.filter { asset in
      matchesText(tokens, asset: asset, enrichment: enrichments[asset.id])
        && matchesFolders(asset)
        && matchesContentType(asset)
        && matchesFileSize(asset)
        && matchesDimensions(asset)
        && matchesColors(enrichments[asset.id])
        && matchesKeywords(enrichments[asset.id])
    }
  }

  private func matchesText(
    _ tokens: [String],
    asset: ImageAsset,
    enrichment: AssetEnrichment?
  ) -> Bool {
    guard !tokens.isEmpty else {
      return true
    }
    let searchable = [
      asset.filename,
      asset.url.path,
      asset.contentType,
      enrichment?.exif.ocrText,
      enrichment?.exif.keywords.joined(separator: " "),
    ]
    .compactMap { $0 }
    .joined(separator: " ")
    .lowercased()
    return tokens.allSatisfy { searchable.contains($0) }
  }

  private func matchesFolders(_ asset: ImageAsset) -> Bool {
    guard !folders.isEmpty else {
      return true
    }
    return folders.contains { asset.url.isContained(in: $0) }
  }

  private func matchesContentType(_ asset: ImageAsset) -> Bool {
    contentTypes.isEmpty || contentTypes.contains(asset.contentType)
  }

  private func matchesFileSize(_ asset: ImageAsset) -> Bool {
    if let minimumFileSize, asset.fileSize < minimumFileSize {
      return false
    }
    if let maximumFileSize, asset.fileSize > maximumFileSize {
      return false
    }
    return true
  }

  private func matchesDimensions(_ asset: ImageAsset) -> Bool {
    if let minimumPixelWidth, (asset.pixelWidth ?? 0) < minimumPixelWidth {
      return false
    }
    if let minimumPixelHeight, (asset.pixelHeight ?? 0) < minimumPixelHeight {
      return false
    }
    return true
  }

  private func matchesColors(_ enrichment: AssetEnrichment?) -> Bool {
    guard !colors.isEmpty else {
      return true
    }
    let availableColors = Set(
      enrichment?.exif.dominantColors.map { $0.lowercased() } ?? []
    )
    return !availableColors.isDisjoint(with: colors)
  }

  private func matchesKeywords(_ enrichment: AssetEnrichment?) -> Bool {
    guard !keywords.isEmpty else {
      return true
    }
    let availableKeywords = Set(
      enrichment?.exif.keywords.map { $0.lowercased() } ?? []
    )
    return !availableKeywords.isDisjoint(with: keywords)
  }
}

public enum SmartAssetView: String, CaseIterable, Sendable {
  case screenshots
  case recentDownloads
  case recentlyModified
  case largeFiles

  public var title: String {
    switch self {
    case .screenshots:
      "Screenshots"
    case .recentDownloads:
      "Recent Downloads"
    case .recentlyModified:
      "Recently Modified"
    case .largeFiles:
      "Large Files"
    }
  }

  public func assets(
    in assets: [ImageAsset],
    now: Date = Date()
  ) -> [ImageAsset] {
    switch self {
    case .screenshots:
      assets.filter { asset in
        let lowercaseName = asset.filename.lowercased()
        return lowercaseName.hasPrefix("screenshot")
          || lowercaseName.hasPrefix("screen shot")
          || lowercaseName.contains("截屏")
          || lowercaseName.contains("截图")
      }
    case .recentDownloads:
      assets.filter { asset in
        asset.url.path.contains("/Downloads/")
          && isWithinLastDays(asset.createdAt ?? asset.modifiedAt, now: now, days: 14)
      }
    case .recentlyModified:
      assets.filter { asset in
        isWithinLastDays(asset.modifiedAt, now: now, days: 14)
      }
    case .largeFiles:
      assets.filter { $0.fileSize >= 50_000_000 }
    }
  }

  private func isWithinLastDays(
    _ date: Date?,
    now: Date,
    days: Double
  ) -> Bool {
    guard let date else {
      return false
    }
    return now.timeIntervalSince(date) <= days * 24 * 60 * 60
  }
}

extension URL {
  fileprivate func isContained(in rootURL: URL) -> Bool {
    let candidatePath = standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path
    return candidatePath == rootPath
      || candidatePath.hasPrefix(rootPath + "/")
  }
}
