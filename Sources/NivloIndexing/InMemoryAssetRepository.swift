import Foundation
import NivloDomain

public actor InMemoryAssetRepository:
  AssetRepository, AssetEnrichmentRepository, LibraryRootRepository
{
  private var storedAssets: [AssetID: ImageAsset]
  private var storedEnrichments: [AssetID: AssetEnrichment] = [:]
  private var storedRoots: [UUID: LibraryRoot] = [:]

  public init(assets: [ImageAsset] = []) {
    storedAssets = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0) })
  }

  public func assets() -> [ImageAsset] {
    storedAssets.values.sorted { $0.url.path < $1.url.path }
  }

  public func upsertAssets(_ assets: [ImageAsset], in rootURL: URL) {
    invalidateChangedEnrichments(for: assets)
    let replacements = Dictionary(
      uniqueKeysWithValues: assets.map { ($0.id, $0) }
    )
    storedAssets = storedAssets.merging(replacements) { _, replacement in
      replacement
    }
  }

  public func replaceAssets(
    in rootURL: URL,
    with assets: [ImageAsset]
  ) -> Int {
    let rootURL = rootURL.standardizedFileURL
    let existingIDs = Set(
      storedAssets.values
        .filter { $0.url.isContained(in: rootURL) }
        .map(\.id)
    )
    let replacementIDs = Set(assets.map(\.id))
    let removedIDs = existingIDs.subtracting(replacementIDs)
    invalidateChangedEnrichments(for: assets)
    let retainedAssets = storedAssets.filter { !removedIDs.contains($0.key) }
    let replacements = Dictionary(
      uniqueKeysWithValues: assets.map { ($0.id, $0) }
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
