import Foundation
import NivloDomain
import NivloPersistence
import Testing

@Suite("SQLite index maintenance")
struct SQLiteIndexMaintenanceTests {
  @Test("persists scan health and failed enrichments")
  func persistsHealth() async throws {
    let databaseURL = maintenanceDatabaseURL()
    let repository = try SQLiteAssetRepository(databaseURL: databaseURL)
    let failure = EnrichmentFailureRecord(
      assetID: AssetID(volumeIdentifier: "volume", fileIdentifier: "broken"),
      message: "Unreadable image",
      failedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )

    try await repository.recordSuccessfulScan(
      at: Date(timeIntervalSince1970: 1_700_000_100)
    )
    try await repository.replaceEnrichmentFailures([failure])

    let reopened = try SQLiteAssetRepository(databaseURL: databaseURL)
    #expect(
      try await reopened.indexHealth().lastSuccessfulScanAt
        == Date(timeIntervalSince1970: 1_700_000_100)
    )
    #expect(try await reopened.enrichmentFailures() == [failure])
  }

  @Test("repairs rich metadata without deleting assets or roots")
  func rebuildsDerivedIndex() async throws {
    let repository = try SQLiteAssetRepository(
      databaseURL: maintenanceDatabaseURL()
    )
    let rootURL = URL(filePath: "/tmp/nivlo-maintenance")
    let asset = maintenanceAsset(rootURL: rootURL)
    let root = LibraryRoot(
      id: UUID(),
      displayName: "Maintenance",
      pathHint: rootURL.path,
      bookmarkData: Data([1, 2, 3]),
      addedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    _ = try await repository.replaceAssets(in: rootURL, with: [asset])
    try await repository.upsertLibraryRoot(root)
    try await repository.upsertEnrichments([maintenanceEnrichment(for: asset.id)])

    try await repository.removeAllEnrichments()
    try await repository.rebuildSearchIndex()

    #expect(try await repository.assets() == [asset])
    #expect(try await repository.libraryRoots() == [root])
    #expect(try await repository.enrichments().isEmpty)
    #expect(try await repository.searchAssets(matching: "asset") == [asset])
    #expect(try await repository.integrityCheck() == "ok")
  }
}

private func maintenanceDatabaseURL() -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "\(UUID().uuidString).sqlite")
}

private func maintenanceAsset(rootURL: URL) -> ImageAsset {
  ImageAsset(
    id: AssetID(volumeIdentifier: "volume", fileIdentifier: "asset"),
    url: rootURL.appending(path: "asset.png"),
    filename: "asset.png",
    contentType: "public.png",
    fileSize: 10,
    createdAt: nil,
    modifiedAt: nil,
    pixelWidth: 2,
    pixelHeight: 2
  )
}

private func maintenanceEnrichment(for id: AssetID) -> AssetEnrichment {
  AssetEnrichment(
    assetID: id,
    exactHash: String(repeating: "a", count: 64),
    perceptualHash: 0,
    thumbnailURL: URL(filePath: "/tmp/thumb.jpg"),
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
    indexedAt: Date()
  )
}
