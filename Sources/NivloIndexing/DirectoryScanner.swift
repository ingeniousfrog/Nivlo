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

public actor DirectoryScanner: DirectoryScanning {
  private let fileManager: FileManager
  private let repository: any AssetRepository
  private let contentLister: any DirectoryContentListing

  public init(
    repository: any AssetRepository,
    fileManager: FileManager = .default,
    contentLister: any DirectoryContentListing = FoundationDirectoryContentLister()
  ) {
    self.repository = repository
    self.fileManager = fileManager
    self.contentLister = contentLister
  }

  public func scan(rootURL: URL) async throws -> ScanSummary {
    let rootURL = rootURL.standardizedFileURL
    guard try isDirectory(rootURL) else {
      throw DirectoryScannerError.invalidRoot(rootURL)
    }

    let discovery = try discoverImages(in: rootURL)
    let removedCount: Int
    if discovery.issueCount == 0 {
      removedCount = try await repository.replaceAssets(
        in: rootURL,
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
      let values: URLResourceValues
      do {
        values = try fileURL.resourceValues(forKeys: Set(resourceKeys))
      } catch {
        issueCount += 1
        continue
      }
      guard values.isRegularFile == true else {
        continue
      }
      guard let contentType = values.contentType, contentType.conforms(to: .image) else {
        skippedCount += 1
        continue
      }
      guard let identity = makeIdentity(for: fileURL, values: values) else {
        skippedCount += 1
        continue
      }

      let dimensions = imageDimensions(at: fileURL)
      assets.append(
        ImageAsset(
          id: identity,
          url: fileURL.standardizedFileURL,
          filename: fileURL.lastPathComponent,
          contentType: contentType.identifier,
          fileSize: Int64(values.fileSize ?? 0),
          createdAt: values.creationDate,
          modifiedAt: values.contentModificationDate,
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
    values: URLResourceValues
  ) -> AssetID? {
    guard
      let fileIdentifier = values.fileResourceIdentifier,
      let volumeIdentifier = values.volumeIdentifier
    else {
      return nil
    }
    return AssetID(
      volumeIdentifier: String(describing: volumeIdentifier),
      fileIdentifier: String(describing: fileIdentifier)
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
