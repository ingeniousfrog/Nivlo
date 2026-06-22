import Foundation
import ImageIO
import NivloDomain
import UniformTypeIdentifiers

public enum DirectoryScannerError: Error, Equatable, LocalizedError, Sendable {
  case invalidRoot(URL)
  case enumerationFailed(URL)

  public var errorDescription: String? {
    switch self {
    case .invalidRoot(let url):
      return "Nivlo couldn’t read \(url.lastPathComponent) as a folder."
    case .enumerationFailed(let url):
      return "Nivlo couldn’t list files in \(url.lastPathComponent)."
    }
  }
}

public struct ScanProgress: Equatable, Sendable {
  public let indexedCount: Int
  public let discoveredCount: Int

  public init(indexedCount: Int, discoveredCount: Int) {
    self.indexedCount = indexedCount
    self.discoveredCount = discoveredCount
  }
}

public typealias ScanProgressHandler = @Sendable (ScanProgress) async -> Void

public struct DirectoryListing: Sendable {
  public let urls: [URL]
  public let issueCount: Int

  public init(urls: [URL], issueCount: Int) {
    self.urls = urls
    self.issueCount = issueCount
  }
}

public protocol DirectoryContentListing: Sendable {
  func contents(
    of rootURL: URL,
    resourceKeys: [URLResourceKey]
  ) throws -> DirectoryListing
}

public struct FileResourceSnapshot: Sendable {
  public let isRegularFile: Bool
  public let contentType: UTType?
  public let fileSize: Int?
  public let createdAt: Date?
  public let modifiedAt: Date?
  public let fileIdentifier: String?
  public let volumeIdentifier: String?

  public init(
    isRegularFile: Bool,
    contentType: UTType?,
    fileSize: Int?,
    createdAt: Date?,
    modifiedAt: Date?,
    fileIdentifier: String?,
    volumeIdentifier: String?
  ) {
    self.isRegularFile = isRegularFile
    self.contentType = contentType
    self.fileSize = fileSize
    self.createdAt = createdAt
    self.modifiedAt = modifiedAt
    self.fileIdentifier = fileIdentifier
    self.volumeIdentifier = volumeIdentifier
  }
}

public protocol FileResourceReading: Sendable {
  func snapshot(for url: URL, keys: Set<URLResourceKey>) throws
    -> FileResourceSnapshot
}

public struct FoundationDirectoryContentLister: DirectoryContentListing {
  public init() {}

  public func contents(
    of rootURL: URL,
    resourceKeys: [URLResourceKey]
  ) throws -> DirectoryListing {
    var issueCount = 0
    guard
      let enumerator = FileManager.default.enumerator(
        at: rootURL,
        includingPropertiesForKeys: resourceKeys,
        options: [.skipsHiddenFiles, .skipsPackageDescendants],
        errorHandler: { _, _ in
          issueCount += 1
          return true
        }
      )
    else {
      throw DirectoryScannerError.enumerationFailed(rootURL)
    }
    return DirectoryListing(
      urls: enumerator.compactMap { $0 as? URL },
      issueCount: issueCount
    )
  }
}

public struct FoundationFileResourceReader: FileResourceReading {
  public init() {}

  public func snapshot(
    for url: URL,
    keys: Set<URLResourceKey>
  ) throws -> FileResourceSnapshot {
    let values = try url.resourceValues(forKeys: keys)
    return FileResourceSnapshot(
      isRegularFile: values.isRegularFile == true,
      contentType: values.contentType,
      fileSize: values.fileSize,
      createdAt: values.creationDate,
      modifiedAt: values.contentModificationDate,
      fileIdentifier: values.fileResourceIdentifier.map { String(describing: $0) },
      volumeIdentifier: values.volumeIdentifier.map { String(describing: $0) }
    )
  }
}

public actor DirectoryScanner: DirectoryScanning {
  private let fileManager: FileManager
  private let repository: any AssetRepository
  private let contentLister: any DirectoryContentListing
  private let resourceReader: any FileResourceReading
  private let batchSize: Int

  public init(
    repository: any AssetRepository,
    fileManager: FileManager = .default,
    contentLister: any DirectoryContentListing = FoundationDirectoryContentLister(),
    resourceReader: any FileResourceReading = FoundationFileResourceReader(),
    batchSize: Int = 1_000
  ) {
    self.repository = repository
    self.fileManager = fileManager
    self.contentLister = contentLister
    self.resourceReader = resourceReader
    self.batchSize = max(1, batchSize)
  }

  public func scan(rootURL: URL) async throws -> ScanSummary {
    try await scan(rootURL: rootURL, progress: nil)
  }

  public func scan(
    rootURL: URL,
    progress: ScanProgressHandler?
  ) async throws -> ScanSummary {
    let rootURL = rootURL.standardizedFileURL
    guard try isDirectory(rootURL) else {
      throw DirectoryScannerError.invalidRoot(rootURL)
    }

    return try await scanValidated(
      scopeURL: rootURL,
      rootURL: rootURL,
      progress: progress
    )
  }

  public func scan(scopeURL: URL, under rootURL: URL) async throws -> ScanSummary {
    let scopeURL = scopeURL.standardizedFileURL
    let rootURL = rootURL.standardizedFileURL
    guard scopeURL.isContained(in: rootURL), try isDirectory(scopeURL) else {
      throw DirectoryScannerError.invalidRoot(scopeURL)
    }

    return try await scanValidated(
      scopeURL: scopeURL,
      rootURL: rootURL,
      progress: nil
    )
  }

  private func scanValidated(
    scopeURL: URL,
    rootURL: URL,
    progress: ScanProgressHandler?
  ) async throws -> ScanSummary {
    let hiddenPaths = try await repository.hiddenAssetPaths(in: rootURL)
    let discovery = try discoverImages(in: scopeURL, hiddenPaths: hiddenPaths)
    let hadExistingAssets: Bool
    if progress == nil {
      hadExistingAssets = true
    } else {
      hadExistingAssets = try await repository.assets().contains {
        $0.url.isContained(in: scopeURL)
      }
    }
    if let progress {
      var indexedCount = 0
      for batch in discovery.assets.chunked(into: batchSize) {
        try await repository.upsertAssets(Array(batch), in: rootURL)
        indexedCount += batch.count
        await progress(
          ScanProgress(
            indexedCount: indexedCount,
            discoveredCount: discovery.assets.count
          )
        )
      }
    }
    let removedCount: Int
    if progress != nil, !hadExistingAssets {
      removedCount = 0
    } else if discovery.issueCount == 0 {
      removedCount = try await repository.replaceAssets(
        in: scopeURL,
        under: rootURL,
        with: discovery.assets
      )
    } else {
      try await repository.upsertAssets(discovery.assets, in: rootURL)
      removedCount = 0
    }
    return ScanSummary(
      discoveredCount: discovery.assets.count,
      indexedCount: discovery.assets.count,
      removedCount: removedCount,
      skippedCount: discovery.skippedCount,
      issueCount: discovery.issueCount
    )
  }

  private func isDirectory(_ url: URL) throws -> Bool {
    let values = try url.resourceValues(forKeys: [.isDirectoryKey])
    return values.isDirectory == true
  }

  private func discoverImages(
    in rootURL: URL,
    hiddenPaths: Set<String>
  ) throws -> DiscoveryResult {
    let resourceKeys: [URLResourceKey] = [
      .isDirectoryKey,
      .isRegularFileKey,
      .isHiddenKey,
      .fileSizeKey,
      .creationDateKey,
      .contentModificationDateKey,
      .contentTypeKey,
      .fileResourceIdentifierKey,
      .volumeIdentifierKey,
    ]
    let listing = try contentLister.contents(
      of: rootURL,
      resourceKeys: resourceKeys
    )

    var assets: [ImageAsset] = []
    var skippedCount = 0
    var issueCount = listing.issueCount
    for fileURL in listing.urls {
      if hiddenPaths.contains(fileURL.standardizedFileURL.path) {
        skippedCount += 1
        continue
      }
      let snapshot: FileResourceSnapshot
      do {
        snapshot = try resourceReader.snapshot(
          for: fileURL,
          keys: Set(resourceKeys)
        )
      } catch {
        issueCount += 1
        continue
      }
      guard snapshot.isRegularFile else {
        continue
      }
      guard let contentType = snapshot.contentType else {
        issueCount += 1
        continue
      }
      guard contentType.isSupportedVisualAsset else {
        skippedCount += 1
        continue
      }
      guard let identity = makeIdentity(for: fileURL, snapshot: snapshot) else {
        issueCount += 1
        continue
      }

      let dimensions: ImageDimensions?
      if contentType.conforms(to: .image) {
        dimensions = imageDimensions(at: fileURL)
      } else {
        dimensions = nil
      }
      assets.append(
        ImageAsset(
          id: identity,
          url: fileURL.standardizedFileURL,
          filename: fileURL.lastPathComponent,
          contentType: contentType.identifier,
          fileSize: Int64(snapshot.fileSize ?? 0),
          createdAt: snapshot.createdAt,
          modifiedAt: snapshot.modifiedAt,
          pixelWidth: dimensions?.width,
          pixelHeight: dimensions?.height
        )
      )
    }

    return DiscoveryResult(
      assets: assets.sorted { $0.url.path < $1.url.path },
      skippedCount: skippedCount,
      issueCount: issueCount
    )
  }

  private func makeIdentity(
    for url: URL,
    snapshot: FileResourceSnapshot
  ) -> AssetID? {
    guard
      let fileIdentifier = snapshot.fileIdentifier,
      let volumeIdentifier = snapshot.volumeIdentifier
    else {
      return nil
    }
    return AssetID(
      volumeIdentifier: volumeIdentifier,
      fileIdentifier: fileIdentifier
    )
  }

  private func imageDimensions(at url: URL) -> ImageDimensions? {
    guard
      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
        as? [CFString: Any],
      let width = properties[kCGImagePropertyPixelWidth] as? Int,
      let height = properties[kCGImagePropertyPixelHeight] as? Int
    else {
      return nil
    }
    return ImageDimensions(width: width, height: height)
  }
}

extension Array {
  fileprivate func chunked(into size: Int) -> [ArraySlice<Element>] {
    guard !isEmpty else {
      return []
    }
    return stride(from: 0, to: count, by: size).map { startIndex in
      self[startIndex..<Swift.min(startIndex + size, count)]
    }
  }
}

private struct DiscoveryResult {
  let assets: [ImageAsset]
  let skippedCount: Int
  let issueCount: Int
}

private struct ImageDimensions {
  let width: Int
  let height: Int
}

extension URL {
  fileprivate func isContained(in rootURL: URL) -> Bool {
    let candidatePath = standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path
    return candidatePath == rootPath
      || candidatePath.hasPrefix(rootPath + "/")
  }
}

extension UTType {
  fileprivate var isSupportedVisualAsset: Bool {
    conforms(to: .image) || conforms(to: .movie)
  }
}
