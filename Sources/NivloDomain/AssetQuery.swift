import Foundation

public struct AssetQuery: Equatable, Sendable {
  public let searchText: String
  public let folders: [URL]
  public let contentTypes: Set<String>
  public let minimumFileSize: Int64?
  public let maximumFileSize: Int64?
  public let minimumPixelWidth: Int?
  public let minimumPixelHeight: Int?
  public let createdAfter: Date?
  public let createdBefore: Date?
  public let modifiedAfter: Date?
  public let modifiedBefore: Date?
  public let colors: Set<String>
  public let keywords: Set<String>
  public let sources: Set<AssetSource>
  public let sort: AssetSort

  public init(
    searchText: String = "",
    folders: [URL] = [],
    contentTypes: Set<String> = [],
    minimumFileSize: Int64? = nil,
    maximumFileSize: Int64? = nil,
    minimumPixelWidth: Int? = nil,
    minimumPixelHeight: Int? = nil,
    createdAfter: Date? = nil,
    createdBefore: Date? = nil,
    modifiedAfter: Date? = nil,
    modifiedBefore: Date? = nil,
    colors: Set<String> = [],
    keywords: Set<String> = [],
    sources: Set<AssetSource> = [],
    sort: AssetSort = .path(order: .ascending)
  ) {
    self.searchText = searchText
    self.folders = folders.map(\.standardizedFileURL)
    self.contentTypes = contentTypes
    self.minimumFileSize = minimumFileSize
    self.maximumFileSize = maximumFileSize
    self.minimumPixelWidth = minimumPixelWidth
    self.minimumPixelHeight = minimumPixelHeight
    self.createdAfter = createdAfter
    self.createdBefore = createdBefore
    self.modifiedAfter = modifiedAfter
    self.modifiedBefore = modifiedBefore
    self.colors = Set(colors.map { $0.lowercased() })
    self.keywords = Set(keywords.map { $0.lowercased() })
    self.sources = sources
    self.sort = sort
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
        && matchesDates(asset)
        && matchesColors(enrichments[asset.id])
        && matchesKeywords(enrichments[asset.id])
        && matchesSources(asset)
    }
    .sorted { sort.areInIncreasingOrder($0, $1) }
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
      enrichment?.exif.dominantColors.joined(separator: " "),
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

  private func matchesDates(_ asset: ImageAsset) -> Bool {
    if let createdAfter, (asset.createdAt ?? .distantPast) < createdAfter {
      return false
    }
    if let createdBefore, (asset.createdAt ?? .distantFuture) > createdBefore {
      return false
    }
    if let modifiedAfter, (asset.modifiedAt ?? .distantPast) < modifiedAfter {
      return false
    }
    if let modifiedBefore, (asset.modifiedAt ?? .distantFuture) > modifiedBefore {
      return false
    }
    return true
  }

  private func matchesSources(_ asset: ImageAsset) -> Bool {
    sources.isEmpty || sources.contains(AssetSourceClassifier.classify(asset.url))
  }
}

public enum AssetSource: String, CaseIterable, Codable, Sendable {
  case desktop
  case downloads
  case documents
  case externalVolume
  case project
  case other
}

public enum AssetSourceClassifier: Sendable {
  public static func classify(_ url: URL) -> AssetSource {
    let components = url.standardizedFileURL.pathComponents
    if components.contains(".git")
      || components.contains("Package.swift")
      || components.contains("node_modules")
    {
      return .project
    }
    if components.starts(with: ["/", "Volumes"]) {
      return .externalVolume
    }
    if components.contains("Downloads") {
      return .downloads
    }
    if components.contains("Desktop") {
      return .desktop
    }
    if components.contains("Documents") {
      return .documents
    }
    return .other
  }
}

public enum SortOrder: Sendable, Equatable {
  case ascending
  case descending
}

public enum AssetSort: Equatable, Sendable {
  case filename(order: SortOrder)
  case path(order: SortOrder)
  case fileSize(order: SortOrder)
  case createdAt(order: SortOrder)
  case modifiedAt(order: SortOrder)
  case dimensions(order: SortOrder)
  case source(order: SortOrder)

  func areInIncreasingOrder(_ first: ImageAsset, _ second: ImageAsset) -> Bool {
    switch self {
    case .filename(let order):
      compare(first.filename.localizedStandardCompare(second.filename), order: order)
    case .path(let order):
      compare(first.url.path.localizedStandardCompare(second.url.path), order: order)
    case .fileSize(let order):
      compare(first.fileSize, second.fileSize, order: order)
    case .createdAt(let order):
      compare(first.createdAt ?? .distantPast, second.createdAt ?? .distantPast, order: order)
    case .modifiedAt(let order):
      compare(first.modifiedAt ?? .distantPast, second.modifiedAt ?? .distantPast, order: order)
    case .dimensions(let order):
      compare(pixelArea(first), pixelArea(second), order: order)
    case .source(let order):
      compare(
        AssetSourceClassifier.classify(first.url).rawValue
          .localizedStandardCompare(AssetSourceClassifier.classify(second.url).rawValue),
        order: order
      )
    }
  }

  private func pixelArea(_ asset: ImageAsset) -> Int {
    (asset.pixelWidth ?? 0) * (asset.pixelHeight ?? 0)
  }

  private func compare<T: Comparable>(
    _ first: T,
    _ second: T,
    order: SortOrder
  ) -> Bool {
    switch order {
    case .ascending:
      first < second
    case .descending:
      first > second
    }
  }

  private func compare(
    _ result: ComparisonResult,
    order: SortOrder
  ) -> Bool {
    switch order {
    case .ascending:
      result == .orderedAscending
    case .descending:
      result == .orderedDescending
    }
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
