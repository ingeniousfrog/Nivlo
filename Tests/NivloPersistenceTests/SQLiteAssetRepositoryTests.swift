import Foundation
import NivloDomain
import Testing

@testable import NivloPersistence

@Suite("SQLite asset repository")
struct SQLiteAssetRepositoryTests {
  @Test("persists assets across repository instances")
  func persistsAcrossInstances() async throws {
    let databaseURL = temporaryDatabaseURL()
    let rootURL = URL(filePath: "/tmp/nivlo-library")
    let expected = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-1"),
      url: rootURL.appending(path: "cover.png")
    )
    let writer = try SQLiteAssetRepository(databaseURL: databaseURL)
    _ = try await writer.replaceAssets(in: rootURL, with: [expected])

    let reader = try SQLiteAssetRepository(databaseURL: databaseURL)
    let assets = try await reader.assets()

    #expect(assets == [expected])
  }

  @Test("replaces only assets contained by the scanned root")
  func replacementIsScopedToRoot() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: temporaryDatabaseURL())
    let firstRoot = URL(filePath: "/tmp/nivlo-first")
    let secondRoot = URL(filePath: "/tmp/nivlo-second")
    let firstAsset = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-1"),
      url: firstRoot.appending(path: "first.png")
    )
    let secondAsset = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-2"),
      url: secondRoot.appending(path: "second.png")
    )
    _ = try await repository.replaceAssets(in: firstRoot, with: [firstAsset])
    _ = try await repository.replaceAssets(in: secondRoot, with: [secondAsset])

    let removedCount = try await repository.replaceAssets(in: firstRoot, with: [])
    let assets = try await repository.assets()

    #expect(removedCount == 1)
    #expect(assets == [secondAsset])
  }

  @Test("updates the path when a stable file identity moves")
  func updatesMovedAssetPath() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: temporaryDatabaseURL())
    let rootURL = URL(filePath: "/tmp/nivlo-library")
    let identity = AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-1")
    let original = makeAsset(
      id: identity,
      url: rootURL.appending(path: "before.png")
    )
    let moved = makeAsset(
      id: identity,
      url: rootURL.appending(path: "nested/after.png")
    )
    _ = try await repository.replaceAssets(in: rootURL, with: [original])

    let removedCount = try await repository.replaceAssets(in: rootURL, with: [moved])
    let assets = try await repository.assets()

    #expect(removedCount == 0)
    #expect(assets == [moved])
  }

  @Test("scoped replacement removes only assets under scope while preserving root")
  func scopedReplacementPreservesOwningRoot() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: temporaryDatabaseURL())
    let rootURL = URL(filePath: "/tmp/nivlo-library")
    let scopeURL = rootURL.appending(path: "icons")
    let nestedOriginal = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-1"),
      url: scopeURL.appending(path: "old.png")
    )
    let nestedReplacement = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-2"),
      url: scopeURL.appending(path: "new.png")
    )
    let sibling = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-3"),
      url: rootURL.appending(path: "logos/keep.png")
    )
    _ = try await repository.replaceAssets(
      in: rootURL,
      with: [nestedOriginal, sibling]
    )

    let removedCount = try await repository.replaceAssets(
      in: scopeURL,
      under: rootURL,
      with: [nestedReplacement]
    )
    let assets = try await repository.assets()
    let finalRemovedCount = try await repository.replaceAssets(
      in: rootURL,
      with: []
    )

    #expect(removedCount == 1)
    #expect(assets == [nestedReplacement, sibling])
    #expect(finalRemovedCount == 2)
  }

  @Test("searches assets with SQLite FTS metadata")
  func searchesAssetsWithFTS() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: temporaryDatabaseURL())
    let rootURL = URL(filePath: "/tmp/nivlo-library")
    let asset = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-fts"),
      url: rootURL.appending(path: "receipt.png")
    )
    _ = try await repository.replaceAssets(in: rootURL, with: [asset])
    try await repository.upsertEnrichments([
      AssetEnrichment(
        assetID: asset.id,
        exactHash: "hash",
        perceptualHash: 42,
        thumbnailURL: URL(filePath: "/tmp/thumb.jpg"),
        exif: AssetEXIF(
          cameraMake: "NivloCam",
          cameraModel: "Desk",
          lensModel: nil,
          capturedAt: nil,
          orientation: nil,
          isoSpeed: nil,
          focalLength: nil,
          aperture: nil,
          exposureTime: nil,
          ocrText: "Invoice paid",
          keywords: ["finance"],
          dominantColors: []
        ),
        indexedAt: Date(timeIntervalSince1970: 1_700_000_200)
      )
    ])

    let results = try await repository.searchAssets(matching: "invoice finance")

    #expect(results == [asset])
  }

  @Test("asset metadata refresh removes stale rich search text")
  func assetRefreshRemovesStaleSearchText() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: temporaryDatabaseURL())
    let rootURL = URL(filePath: "/tmp/nivlo-library")
    let identity = AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-fts")
    let original = makeAsset(id: identity, url: rootURL.appending(path: "receipt.png"))
    _ = try await repository.replaceAssets(in: rootURL, with: [original])
    try await repository.upsertEnrichments([
      AssetEnrichment(
        assetID: original.id,
        exactHash: "hash",
        perceptualHash: 42,
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
          exposureTime: nil,
          ocrText: "obsolete",
          keywords: [],
          dominantColors: []
        ),
        indexedAt: Date(timeIntervalSince1970: 1_700_000_200)
      )
    ])
    let refreshed = ImageAsset(
      id: identity,
      url: rootURL.appending(path: "receipt.png"),
      filename: "receipt.png",
      contentType: "public.png",
      fileSize: 2_048,
      createdAt: original.createdAt,
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_300),
      pixelWidth: original.pixelWidth,
      pixelHeight: original.pixelHeight
    )

    _ = try await repository.replaceAssets(in: rootURL, with: [refreshed])
    let results = try await repository.searchAssets(matching: "obsolete")

    #expect(results.isEmpty)
  }

  @Test("hidden assets stay out of the index after rescans")
  func hiddenAssetsStayOutOfIndex() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: temporaryDatabaseURL())
    let rootURL = URL(filePath: "/tmp/nivlo-library")
    let hidden = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-hidden"),
      url: rootURL.appending(path: "hidden.png")
    )
    let visible = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-visible"),
      url: rootURL.appending(path: "visible.png")
    )
    _ = try await repository.replaceAssets(in: rootURL, with: [hidden, visible])

    try await repository.hideAsset(hidden)
    _ = try await repository.replaceAssets(in: rootURL, with: [hidden, visible])

    #expect(try await repository.assets() == [visible])
    #expect(try await repository.hiddenAssetPaths(in: rootURL) == Set([hidden.url.path]))
  }

  @Test("hidden assets retain metadata and can be restored")
  func hiddenAssetsCanBeRestored() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: temporaryDatabaseURL())
    let rootURL = URL(filePath: "/tmp/nivlo-library")
    let hidden = makeAsset(
      id: AssetID(volumeIdentifier: "volume-a", fileIdentifier: "file-hidden"),
      url: rootURL.appending(path: "hidden.png")
    )
    _ = try await repository.replaceAssets(in: rootURL, with: [hidden])

    try await repository.hideAsset(hidden)
    let records = try await repository.hiddenAssets()
    try await repository.unhideAsset(at: hidden.url)
    _ = try await repository.replaceAssets(in: rootURL, with: [hidden])

    #expect(records.count == 1)
    #expect(records.first?.asset == hidden)
    #expect(try await repository.hiddenAssets().isEmpty)
    #expect(try await repository.assets() == [hidden])
  }
}

private func temporaryDatabaseURL() -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "\(UUID().uuidString).sqlite")
}

private func makeAsset(id: AssetID, url: URL) -> ImageAsset {
  ImageAsset(
    id: id,
    url: url,
    filename: url.lastPathComponent,
    contentType: "public.png",
    fileSize: 1_024,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
    pixelWidth: 1920,
    pixelHeight: 1080
  )
}
