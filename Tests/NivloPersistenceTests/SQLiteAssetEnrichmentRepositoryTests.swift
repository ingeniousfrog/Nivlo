import Foundation
import NivloDomain
import NivloPersistence
import Testing

@Suite("SQLite asset enrichment repository")
struct SQLiteAssetEnrichmentRepositoryTests {
  @Test("persists enrichment data across repository instances")
  func persistsEnrichment() async throws {
    let databaseURL = enrichmentDatabaseURL()
    let rootURL = URL(filePath: "/tmp/nivlo-enrichment")
    let asset = enrichmentAsset(rootURL: rootURL)
    let expected = enrichment(for: asset.id)
    let writer = try SQLiteAssetRepository(databaseURL: databaseURL)
    _ = try await writer.replaceAssets(in: rootURL, with: [asset])

    try await writer.upsertEnrichments([expected])

    let reader = try SQLiteAssetRepository(databaseURL: databaseURL)
    #expect(try await reader.enrichments() == [expected])
  }

  @Test("deleting an indexed asset also removes its derived enrichment")
  func removesOrphanedEnrichment() async throws {
    let repository = try SQLiteAssetRepository(
      databaseURL: enrichmentDatabaseURL()
    )
    let rootURL = URL(filePath: "/tmp/nivlo-enrichment")
    let asset = enrichmentAsset(rootURL: rootURL)
    _ = try await repository.replaceAssets(in: rootURL, with: [asset])
    try await repository.upsertEnrichments([enrichment(for: asset.id)])

    _ = try await repository.replaceAssets(in: rootURL, with: [])

    #expect(try await repository.enrichments().isEmpty)
  }

  @Test("round trips the full unsigned perceptual hash range")
  func preservesUnsignedHash() async throws {
    let repository = try SQLiteAssetRepository(
      databaseURL: enrichmentDatabaseURL()
    )
    let rootURL = URL(filePath: "/tmp/nivlo-enrichment")
    let asset = enrichmentAsset(rootURL: rootURL)
    let expected = AssetEnrichment(
      assetID: asset.id,
      exactHash: String(repeating: "f", count: 64),
      perceptualHash: UInt64.max,
      thumbnailURL: URL(filePath: "/tmp/cache/maximum.jpg"),
      exif: emptyEXIF(),
      indexedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = try await repository.replaceAssets(in: rootURL, with: [asset])

    try await repository.upsertEnrichments([expected])

    #expect(try await repository.enrichments() == [expected])
  }

  @Test("changing source metadata invalidates stale derived enrichment")
  func invalidatesChangedAsset() async throws {
    let repository = try SQLiteAssetRepository(
      databaseURL: enrichmentDatabaseURL()
    )
    let rootURL = URL(filePath: "/tmp/nivlo-enrichment")
    let original = enrichmentAsset(rootURL: rootURL)
    let changed = ImageAsset(
      id: original.id,
      url: original.url,
      filename: original.filename,
      contentType: original.contentType,
      fileSize: original.fileSize + 1,
      createdAt: original.createdAt,
      modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
      pixelWidth: original.pixelWidth,
      pixelHeight: original.pixelHeight
    )
    _ = try await repository.replaceAssets(in: rootURL, with: [original])
    try await repository.upsertEnrichments([enrichment(for: original.id)])

    _ = try await repository.replaceAssets(in: rootURL, with: [changed])

    #expect(try await repository.enrichments().isEmpty)
  }
}

private func enrichmentDatabaseURL() -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "\(UUID().uuidString).sqlite")
}

private func enrichmentAsset(rootURL: URL) -> ImageAsset {
  ImageAsset(
    id: AssetID(volumeIdentifier: "volume", fileIdentifier: "asset"),
    url: rootURL.appending(path: "asset.png"),
    filename: "asset.png",
    contentType: "public.png",
    fileSize: 100,
    createdAt: nil,
    modifiedAt: nil,
    pixelWidth: 20,
    pixelHeight: 10
  )
}

private func enrichment(for id: AssetID) -> AssetEnrichment {
  AssetEnrichment(
    assetID: id,
    exactHash: String(repeating: "a", count: 64),
    perceptualHash: 0xFEDC_BA98_7654_3210,
    thumbnailURL: URL(filePath: "/tmp/cache/asset.jpg"),
    exif: AssetEXIF(
      cameraMake: "Nivlo",
      cameraModel: "One",
      lensModel: "Local 35mm",
      capturedAt: Date(timeIntervalSince1970: 1_600_000_000),
      orientation: 1,
      isoSpeed: 200,
      focalLength: 35,
      aperture: 2.8,
      exposureTime: 0.01
    ),
    indexedAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}

private func emptyEXIF() -> AssetEXIF {
  AssetEXIF(
    cameraMake: nil,
    cameraModel: nil,
    lensModel: nil,
    capturedAt: nil,
    orientation: nil,
    isoSpeed: nil,
    focalLength: nil,
    aperture: nil,
    exposureTime: nil
  )
}
