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
