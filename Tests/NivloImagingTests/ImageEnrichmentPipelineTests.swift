import Foundation
import NivloDomain
import Testing

@testable import NivloImaging

@Suite("Image enrichment pipeline")
struct ImageEnrichmentPipelineTests {
  @Test("enriches only assets without a current enrichment")
  func enrichesMissingAssets() async throws {
    let first = pipelineAsset(fileID: "first")
    let second = pipelineAsset(fileID: "second")
    let repository = PipelineRepository(
      enrichments: [pipelineEnrichment(for: first.id)]
    )
    let enricher = PipelineEnricher()
    let pipeline = ImageEnrichmentPipeline(
      repository: repository,
      enricher: enricher
    )

    let summary = try await pipeline.enrich([first, second])

    #expect(summary.completedCount == 1)
    #expect(summary.skippedCount == 1)
    #expect(summary.failures.isEmpty)
    #expect(await enricher.enrichedIDs() == [second.id])
    #expect(await repository.enrichments().count == 2)
  }

  @Test("isolates a corrupt image and persists successful enrichments")
  func isolatesFailures() async throws {
    let good = pipelineAsset(fileID: "good")
    let broken = pipelineAsset(fileID: "broken")
    let repository = PipelineRepository()
    let enricher = PipelineEnricher(failingIDs: [broken.id])
    let pipeline = ImageEnrichmentPipeline(
      repository: repository,
      enricher: enricher
    )

    let summary = try await pipeline.enrich([good, broken])

    #expect(summary.completedCount == 1)
    #expect(summary.failures.map(\.assetID) == [broken.id])
    #expect(await repository.enrichments().map(\.assetID) == [good.id])
  }
}

private actor PipelineRepository: AssetEnrichmentRepository {
  private var stored: [AssetID: AssetEnrichment]

  init(enrichments: [AssetEnrichment] = []) {
    stored = Dictionary(
      uniqueKeysWithValues: enrichments.map { ($0.assetID, $0) }
    )
  }

  func enrichments() -> [AssetEnrichment] {
    stored.values.sorted {
      $0.assetID.fileIdentifier < $1.assetID.fileIdentifier
    }
  }

  func upsertEnrichments(_ enrichments: [AssetEnrichment]) {
    let replacements = Dictionary(
      uniqueKeysWithValues: enrichments.map { ($0.assetID, $0) }
    )
    stored = stored.merging(replacements) { _, replacement in replacement }
  }
}

private actor PipelineEnricher: AssetImageEnriching {
  private let failingIDs: Set<AssetID>
  private var processedIDs: [AssetID] = []

  init(failingIDs: Set<AssetID> = []) {
    self.failingIDs = failingIDs
  }

  func enrich(_ asset: ImageAsset) throws -> AssetEnrichment {
    processedIDs.append(asset.id)
    guard !failingIDs.contains(asset.id) else {
      throw PipelineError.corrupt
    }
    return pipelineEnrichment(for: asset.id)
  }

  func enrichedIDs() -> [AssetID] {
    processedIDs
  }
}

private func pipelineAsset(fileID: String) -> ImageAsset {
  ImageAsset(
    id: AssetID(volumeIdentifier: "volume", fileIdentifier: fileID),
    url: URL(filePath: "/tmp/\(fileID).png"),
    filename: "\(fileID).png",
    contentType: "public.png",
    fileSize: 1,
    createdAt: nil,
    modifiedAt: nil,
    pixelWidth: 1,
    pixelHeight: 1
  )
}

private func pipelineEnrichment(for id: AssetID) -> AssetEnrichment {
  AssetEnrichment(
    assetID: id,
    exactHash: String(repeating: "a", count: 64),
    perceptualHash: 0,
    thumbnailURL: URL(filePath: "/tmp/\(id.fileIdentifier).jpg"),
    exif: AssetEXIF(
      cameraMake: nil,
      cameraModel: nil,
      lensModel: nil,
      capturedAt: nil,
      orientation: nil,
      isoSpeed: nil,
      focalLength: nil,
      aperture: nil,
      exposureTime: nil
    ),
    indexedAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private enum PipelineError: Error {
  case corrupt
}
