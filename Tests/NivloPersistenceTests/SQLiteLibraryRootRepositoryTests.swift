import Foundation
import NivloDomain
import NivloPersistence
import Testing

@Suite("SQLite library root repository")
struct SQLiteLibraryRootRepositoryTests {
  @Test("persists authorized roots across repository instances")
  func persistsRoots() async throws {
    let databaseURL = rootDatabaseURL()
    let expected = makeRoot(path: "/tmp/photos")
    let writer = try SQLiteAssetRepository(databaseURL: databaseURL)

    try await writer.upsertLibraryRoot(expected)

    let reader = try SQLiteAssetRepository(databaseURL: databaseURL)
    let roots = try await reader.libraryRoots()
    #expect(roots == [expected])
  }

  @Test("updates refreshed bookmark data without duplicating a root")
  func updatesBookmark() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: rootDatabaseURL())
    let original = makeRoot(path: "/tmp/photos")
    let refreshed = LibraryRoot(
      id: original.id,
      displayName: original.displayName,
      pathHint: "/Volumes/Archive/photos",
      bookmarkData: Data("refreshed".utf8),
      addedAt: original.addedAt
    )
    try await repository.upsertLibraryRoot(original)

    try await repository.upsertLibraryRoot(refreshed)
    let roots = try await repository.libraryRoots()

    #expect(roots == [refreshed])
  }

  @Test("removes an authorized root without deleting indexed assets")
  func removesRootOnly() async throws {
    let repository = try SQLiteAssetRepository(databaseURL: rootDatabaseURL())
    let root = makeRoot(path: "/tmp/photos")
    let asset = ImageAsset(
      id: AssetID(volumeIdentifier: "volume", fileIdentifier: "file"),
      url: URL(filePath: root.pathHint).appending(path: "asset.png"),
      filename: "asset.png",
      contentType: "public.png",
      fileSize: 1,
      createdAt: nil,
      modifiedAt: nil,
      pixelWidth: 1,
      pixelHeight: 1
    )
    try await repository.upsertLibraryRoot(root)
    _ = try await repository.replaceAssets(
      in: URL(filePath: root.pathHint),
      with: [asset]
    )

    try await repository.removeLibraryRoot(id: root.id)

    #expect(try await repository.libraryRoots().isEmpty)
    #expect(try await repository.assets() == [asset])
  }
}

private func rootDatabaseURL() -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "\(UUID().uuidString).sqlite")
}

private func makeRoot(path: String) -> LibraryRoot {
  LibraryRoot(
    id: UUID(uuidString: "CEB7953C-DF3A-464A-823E-E2A9DC7F2563")!,
    displayName: URL(filePath: path).lastPathComponent,
    pathHint: path,
    bookmarkData: Data("bookmark".utf8),
    addedAt: Date(timeIntervalSince1970: 1_700_000_000)
  )
}
