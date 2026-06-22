import Foundation

public struct ScanSummary: Equatable, Sendable {
  public let discoveredCount: Int
  public let indexedCount: Int
  public let removedCount: Int
  public let skippedCount: Int
  public let issueCount: Int

  public init(
    discoveredCount: Int,
    indexedCount: Int,
    removedCount: Int,
    skippedCount: Int,
    issueCount: Int = 0
  ) {
    self.discoveredCount = discoveredCount
    self.indexedCount = indexedCount
    self.removedCount = removedCount
    self.skippedCount = skippedCount
    self.issueCount = issueCount
  }
}

public protocol AssetRepository: Sendable {
  func assets() async throws -> [ImageAsset]
  func searchAssets(matching query: String) async throws -> [ImageAsset]
  func hiddenAssets() async throws -> [HiddenAssetRecord]
  func hiddenAssetPaths(in rootURL: URL) async throws -> Set<String>
  func hideAsset(_ asset: ImageAsset) async throws
  func unhideAsset(at url: URL) async throws
  func upsertAssets(_ assets: [ImageAsset], in rootURL: URL) async throws
  func replaceAssets(in rootURL: URL, with assets: [ImageAsset]) async throws -> Int
  func replaceAssets(
    in scopeURL: URL,
    under rootURL: URL,
    with assets: [ImageAsset]
  ) async throws -> Int
}

public struct HiddenAssetRecord: Identifiable, Equatable, Sendable {
  public var id: String { url.standardizedFileURL.path }

  public let url: URL
  public let hiddenAt: Date
  public let asset: ImageAsset?

  public init(url: URL, hiddenAt: Date, asset: ImageAsset?) {
    self.url = url
    self.hiddenAt = hiddenAt
    self.asset = asset
  }
}

public protocol DirectoryScanning: Sendable {
  func scan(rootURL: URL) async throws -> ScanSummary
  func scan(scopeURL: URL, under rootURL: URL) async throws -> ScanSummary
}

public struct LibraryRoot: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let displayName: String
  public let pathHint: String
  public let bookmarkData: Data
  public let addedAt: Date

  public init(
    id: UUID,
    displayName: String,
    pathHint: String,
    bookmarkData: Data,
    addedAt: Date
  ) {
    self.id = id
    self.displayName = displayName
    self.pathHint = pathHint
    self.bookmarkData = bookmarkData
    self.addedAt = addedAt
  }
}

public protocol LibraryRootRepository: Sendable {
  func libraryRoots() async throws -> [LibraryRoot]
  func upsertLibraryRoot(_ root: LibraryRoot) async throws
  func removeLibraryRoot(id: UUID) async throws
}
