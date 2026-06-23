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
  public let cancelledCount: Int
  public let failures: [AssetEnrichmentFailure]

  public init(
    completedCount: Int,
    skippedCount: Int,
    cancelledCount: Int = 0,
    failures: [AssetEnrichmentFailure]
  ) {
    self.completedCount = completedCount
    self.skippedCount = skippedCount
    self.cancelledCount = cancelledCount
    self.failures = failures
  }
}

public enum ImageEnrichmentPipelineState: Equatable, Sendable {
  case idle
  case running
  case paused
  case cancelling
}

public actor ImageEnrichmentPipeline {
  private let repository: any AssetEnrichmentRepository
  private let enricher: any AssetImageEnriching
  private let maximumConcurrentTasks: Int
  public private(set) var state: ImageEnrichmentPipelineState = .idle

  public init(
    repository: any AssetEnrichmentRepository,
    enricher: any AssetImageEnriching,
    maximumConcurrentTasks: Int = 4
  ) {
    self.repository = repository
    self.enricher = enricher
    self.maximumConcurrentTasks = max(1, maximumConcurrentTasks)
  }

  public func enrich(
    _ assets: [ImageAsset]
  ) async throws -> AssetEnrichmentSummary {
    guard state == .idle else {
      return AssetEnrichmentSummary(
        completedCount: 0,
        skippedCount: assets.count,
        failures: []
      )
    }
    state = .running
    defer { state = .idle }
    let existingIDs = Set(
      try await repository.enrichments().map(\.assetID)
    )
    let pendingAssets = assets.filter { !existingIDs.contains($0.id) }
    var completedCount = 0
    var failures: [AssetEnrichmentFailure] = []
    var nextIndex = 0

    while nextIndex < pendingAssets.count {
      guard await waitUntilRunnable() else {
        break
      }
      let endIndex = min(
        pendingAssets.count,
        nextIndex + maximumConcurrentTasks
      )
      let batch = Array(pendingAssets[nextIndex..<endIndex])
      let results = await withTaskGroup(
        of: EnrichmentTaskResult.self,
        returning: [EnrichmentTaskResult].self
      ) { group in
        for asset in batch {
          group.addTask { [enricher] in
            do {
              return .success(try await enricher.enrich(asset))
            } catch {
              return .failure(
                AssetEnrichmentFailure(
                  assetID: asset.id,
                  message: error.localizedDescription
                )
              )
            }
          }
        }
        var results: [EnrichmentTaskResult] = []
        for await result in group {
          results.append(result)
        }
        return results
      }
      let completed = results.compactMap(\.enrichment)
      failures.append(contentsOf: results.compactMap(\.failure))
      try await repository.upsertEnrichments(completed)
      completedCount += completed.count
      nextIndex = endIndex
    }

    return AssetEnrichmentSummary(
      completedCount: completedCount,
      skippedCount: assets.count - pendingAssets.count,
      cancelledCount: pendingAssets.count - nextIndex,
      failures: failures
    )
  }

  public func pause() {
    guard state == .running else { return }
    state = .paused
  }

  public func resume() {
    guard state == .paused else { return }
    state = .running
  }

  public func cancel() {
    guard state == .running || state == .paused else { return }
    state = .cancelling
  }

  private func waitUntilRunnable() async -> Bool {
    while state == .paused {
      try? await Task.sleep(for: .milliseconds(25))
    }
    return state != .cancelling && !Task.isCancelled
  }
}

private enum EnrichmentTaskResult: Sendable {
  case success(AssetEnrichment)
  case failure(AssetEnrichmentFailure)

  var enrichment: AssetEnrichment? {
    guard case .success(let enrichment) = self else { return nil }
    return enrichment
  }

  var failure: AssetEnrichmentFailure? {
    guard case .failure(let failure) = self else { return nil }
    return failure
  }
}
