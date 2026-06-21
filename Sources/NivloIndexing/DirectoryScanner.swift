import Foundation
import ImageIO
import NivloDomain
import UniformTypeIdentifiers

public enum DirectoryScannerError: Error, Equatable, Sendable {
  case invalidRoot(URL)
  case enumerationFailed(URL)
}

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

  public init(
    repository: any AssetRepository,
    fileManager: FileManager = .default,
    contentLister: any DirectoryContentListing = FoundationDirectoryContentLister(),
    resourceReader: any FileResourceReading = FoundationFileResourceReader()
  ) {
    self.repository = repository
    self.fileManager = fileManager
    self.contentLister = contentLister
    self.resourceReader = resourceReader
  }

  public func scan(rootURL: URL) async throws -> ScanSummary {
    let rootURL = rootURL.standardizedFileURL
    guard try isDirectory(rootURL) else {
      throw DirectoryScannerError.invalidRoot(rootURL)
    }

    return try await scanValidated(scopeURL: rootURL, rootURL: rootURL)
  }

  public func scan(scopeURL: URL, under rootURL: URL) async throws -> ScanSummary {
    let scopeURL = scopeURL.standardizedFileURL
    let rootURL = rootURL.standardizedFileURL
    guard scopeURL.isContained(in: rootURL), try isDirectory(scopeURL) else {
      throw DirectoryScannerError.invalidRoot(scopeURL)
    }

    return try await scanValidated(scopeURL: scopeURL, rootURL: rootURL)
  }

  private func scanValidated(
    scopeURL: URL,
    rootURL: URL
  ) async throws -> ScanSummary {
    let discovery = try discoverImages(in: scopeURL)
    let removedCount: Int
    if discovery.issueCount == 0 {
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

  private func discoverImages(in rootURL: URL) throws -> DiscoveryResult {
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
      guard contentType.conforms(to: .image) else {
        skippedCount += 1
        continue
      }
      guard let identity = makeIdentity(for: fileURL, snapshot: snapshot) else {
        issueCount += 1
        continue
      }

      let dimensions = imageDimensions(at: fileURL)
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
