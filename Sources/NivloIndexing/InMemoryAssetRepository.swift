import Foundation
import NivloDomain

public actor InMemoryAssetRepository:
  AssetRepository, AssetEnrichmentRepository, LibraryRootRepository,
  ProcessingHistoryRepository
{
  private var storedAssets: [AssetID: ImageAsset]
  private var hiddenRecords: [String: HiddenAssetRecord] = [:]
  private var storedEnrichments: [AssetID: AssetEnrichment] = [:]
  private var storedRoots: [UUID: LibraryRoot] = [:]
  private var storedProcessingHistory: [AssetID: [ProcessingHistoryRecord]] = [:]

  public init(assets: [ImageAsset] = []) {
    storedAssets = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
  }

  public func assets() -> [ImageAsset] {
    storedAssets.values.sorted { $0.url.path < $1.url.path }
  }

  public func searchAssets(matching query: String) -> [ImageAsset] {
    AssetQuery(searchText: query)
      .apply(to: assets(), enrichments: storedEnrichments)
  }

  public func hiddenAssets() -> [HiddenAssetRecord] {
    hiddenRecords.values.sorted { $0.hiddenAt > $1.hiddenAt }
  }

  public func hiddenAssetPaths(in rootURL: URL) -> Set<String> {
    let rootURL = rootURL.standardizedFileURL
    return Set(
      hiddenRecords.keys.filter { URL(filePath: $0).isContained(in: rootURL) }
    )
  }

  public func hideAsset(_ asset: ImageAsset) {
    let path = asset.url.standardizedFileURL.path
    hiddenRecords[path] = HiddenAssetRecord(
      url: asset.url.standardizedFileURL,
      hiddenAt: Date(),
      asset: asset
    )
    storedAssets[asset.id] = nil
    storedEnrichments[asset.id] = nil
  }

  public func hideAsset(at url: URL) {
    let standardizedURL = url.standardizedFileURL
    hiddenRecords[standardizedURL.path] = HiddenAssetRecord(
      url: standardizedURL,
      hiddenAt: Date(),
      asset: nil
    )
  }

  public func unhideAsset(at url: URL) {
    hiddenRecords[url.standardizedFileURL.path] = nil
  }

  public func upsertAssets(_ assets: [ImageAsset], in rootURL: URL) {
    let visibleAssets = assets.filter {
      hiddenRecords[$0.url.standardizedFileURL.path] == nil
    }
    invalidateChangedEnrichments(for: visibleAssets)
    let replacements = Dictionary(
      uniqueKeysWithValues: visibleAssets.map { ($0.id, $0) }
    )
    storedAssets = storedAssets.merging(replacements) { _, replacement in
      replacement
    }
  }

  public func replaceAssets(
    in rootURL: URL,
    with assets: [ImageAsset]
  ) -> Int {
    replaceAssets(in: rootURL, under: rootURL, with: assets)
  }

  public func replaceAssets(
    in scopeURL: URL,
    under rootURL: URL,
    with assets: [ImageAsset]
  ) -> Int {
    let scopeURL = scopeURL.standardizedFileURL
    let visibleAssets = assets.filter {
      hiddenRecords[$0.url.standardizedFileURL.path] == nil
    }
    let existingIDs = Set(
      storedAssets.values
        .filter { $0.url.isContained(in: scopeURL) }
        .map(\.id)
    )
    let replacementIDs = Set(visibleAssets.map(\.id))
    let removedIDs = existingIDs.subtracting(replacementIDs)
    invalidateChangedEnrichments(for: visibleAssets)
    let retainedAssets = storedAssets.filter { !removedIDs.contains($0.key) }
    let replacements = Dictionary(
      uniqueKeysWithValues: visibleAssets.map { ($0.id, $0) }
    )
    storedAssets = retainedAssets.merging(replacements) { _, replacement in
      replacement
    }
    storedEnrichments = storedEnrichments.filter {
      storedAssets[$0.key] != nil
    }
    return removedIDs.count
  }

  public func enrichments() -> [AssetEnrichment] {
    storedEnrichments.values.sorted {
      if $0.assetID.volumeIdentifier == $1.assetID.volumeIdentifier {
        return $0.assetID.fileIdentifier < $1.assetID.fileIdentifier
      }
      return $0.assetID.volumeIdentifier < $1.assetID.volumeIdentifier
    }
  }

  public func upsertEnrichments(_ enrichments: [AssetEnrichment]) {
    let replacements = Dictionary(
      uniqueKeysWithValues: enrichments.map { ($0.assetID, $0) }
    )
    storedEnrichments = storedEnrichments.merging(replacements) {
      _, replacement in replacement
    }
  }

  public func libraryRoots() -> [LibraryRoot] {
    storedRoots.values.sorted { $0.addedAt < $1.addedAt }
  }

  public func upsertLibraryRoot(_ root: LibraryRoot) {
    storedRoots[root.id] = root
  }

  public func removeLibraryRoot(id: UUID) {
    storedRoots[id] = nil
  }

  public func appendProcessingHistory(_ records: [ProcessingHistoryRecord]) {
    for record in records {
      storedProcessingHistory[record.sourceAssetID, default: []].append(record)
    }
  }

  public func processingHistory(for assetID: AssetID) -> [ProcessingHistoryRecord] {
    storedProcessingHistory[assetID, default: []]
      .sorted { $0.createdAt < $1.createdAt }
  }

  private func invalidateChangedEnrichments(
    for assets: [ImageAsset]
  ) {
    for asset in assets {
      guard let existing = storedAssets[asset.id] else {
        continue
      }
      if existing.fileSize != asset.fileSize
        || existing.modifiedAt != asset.modifiedAt
      {
        storedEnrichments[asset.id] = nil
      }
    }
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
