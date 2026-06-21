import Foundation
import NivloDomain

public protocol AssetImageEnriching: Sendable {
  func enrich(_ asset: ImageAsset) async throws -> AssetEnrichment
}

public struct AssetEnrichmentFailure: Equatable, Sendable {
  public let assetID: AssetID
  public let message: String

  public init(assetID: AssetID, message: String) {
    self.assetID = assetID
    self.message = message
  }
}

public struct AssetEnrichmentSummary: Equatable, Sendable {
  public let completedCount: Int
  public let skippedCount: Int
  public let failures: [AssetEnrichmentFailure]

  public init(
    completedCount: Int,
    skippedCount: Int,
    failures: [AssetEnrichmentFailure]
  ) {
    self.completedCount = completedCount
    self.skippedCount = skippedCount
    self.failures = failures
  }
}

public actor ImageEnrichmentPipeline {
  private let repository: any AssetEnrichmentRepository
  private let enricher: any AssetImageEnriching

  public init(
    repository: any AssetEnrichmentRepository,
    enricher: any AssetImageEnriching
  ) {
    self.repository = repository
    self.enricher = enricher
  }

  public func enrich(
    _ assets: [ImageAsset]
  ) async throws -> AssetEnrichmentSummary {
    let existingIDs = Set(
      try await repository.enrichments().map(\.assetID)
    )
    let pendingAssets = assets.filter { !existingIDs.contains($0.id) }
    var completed: [AssetEnrichment] = []
    var failures: [AssetEnrichmentFailure] = []

    for asset in pendingAssets {
      do {
        completed.append(try await enricher.enrich(asset))
      } catch {
        failures.append(
          AssetEnrichmentFailure(
            assetID: asset.id,
            message: error.localizedDescription
          )
        )
      }
    }
    try await repository.upsertEnrichments(completed)
    return AssetEnrichmentSummary(
      completedCount: completed.count,
      skippedCount: assets.count - pendingAssets.count,
      failures: failures
    )
  }
}
