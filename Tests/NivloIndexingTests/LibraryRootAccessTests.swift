import Foundation
import NivloDomain
import Testing

@testable import NivloIndexing

@Suite("Library root access")
struct LibraryRootAccessTests {
  @Test("registers a bookmark and keeps the selected root active")
  func registersRoot() async throws {
    let repository = InMemoryLibraryRootRepository()
    let bookmarks = BookmarkProviderStub()
    let manager = LibraryRootAccessManager(
      repository: repository,
      bookmarkProvider: bookmarks,
      now: { Date(timeIntervalSince1970: 1_700_000_000) }
    )
    let url = URL(filePath: "/tmp/photos")

    let root = try await manager.register(url: url)

    #expect(root.displayName == "photos")
    #expect(root.pathHint == "/tmp/photos")
    #expect(root.bookmarkData == Data("created:/tmp/photos".utf8))
    #expect(await repository.libraryRoots() == [root])
    #expect(await manager.activeURLs() == [url])
  }

  @Test("restores bookmarks and refreshes stale bookmark data")
  func refreshesStaleBookmark() async throws {
    let original = LibraryRoot(
      id: UUID(),
      displayName: "photos",
      pathHint: "/old/photos",
      bookmarkData: Data("stale".utf8),
      addedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let repository = InMemoryLibraryRootRepository(roots: [original])
    let bookmarks = BookmarkProviderStub(
      resolutions: [
        original.bookmarkData: ResolvedBookmark(
          url: URL(filePath: "/Volumes/Photos"),
          isStale: true
        )
      ]
    )
    let manager = LibraryRootAccessManager(
      repository: repository,
      bookmarkProvider: bookmarks
    )

    let result = await manager.restore()
    let roots = await repository.libraryRoots()

    #expect(result.restoredRoots.map(\.url) == [URL(filePath: "/Volumes/Photos")])
    #expect(result.failures.isEmpty)
    #expect(roots.first?.pathHint == "/Volumes/Photos")
    #expect(roots.first?.bookmarkData == Data("created:/Volumes/Photos".utf8))
  }

  @Test("reports one failed bookmark without preventing other roots from restoring")
  func isolatesRestoreFailures() async throws {
    let broken = LibraryRoot(
      id: UUID(),
      displayName: "broken",
      pathHint: "/broken",
      bookmarkData: Data("broken".utf8),
      addedAt: .distantPast
    )
    let valid = LibraryRoot(
      id: UUID(),
      displayName: "valid",
      pathHint: "/valid",
      bookmarkData: Data("valid".utf8),
      addedAt: .distantPast
    )
    let repository = InMemoryLibraryRootRepository(roots: [broken, valid])
    let bookmarks = BookmarkProviderStub(
      resolutions: [
        valid.bookmarkData: ResolvedBookmark(
          url: URL(filePath: "/valid"),
          isStale: false
        )
      ]
    )
    let manager = LibraryRootAccessManager(
      repository: repository,
      bookmarkProvider: bookmarks
    )

    let result = await manager.restore()

    #expect(result.restoredRoots.map(\.root.id) == [valid.id])
    #expect(result.failures.map(\.rootID) == [broken.id])
  }

  @Test("removing a root releases its security scope")
  func removeReleasesScope() async throws {
    let repository = InMemoryLibraryRootRepository()
    let bookmarks = BookmarkProviderSpy()
    let manager = LibraryRootAccessManager(
      repository: repository,
      bookmarkProvider: bookmarks
    )
    let root = try await manager.register(url: URL(filePath: "/tmp/photos"))

    try await manager.remove(rootID: root.id)

    #expect(await repository.libraryRoots().isEmpty)
    #expect(bookmarks.stoppedURLs() == [URL(filePath: "/tmp/photos")])
  }

  @Test("releasing the manager stops every active security scope")
  func releaseAllScopes() async throws {
    let repository = InMemoryLibraryRootRepository()
    let bookmarks = BookmarkProviderSpy()
    let manager = LibraryRootAccessManager(
      repository: repository,
      bookmarkProvider: bookmarks
    )
    _ = try await manager.register(url: URL(filePath: "/tmp/first"))
    _ = try await manager.register(url: URL(filePath: "/tmp/second"))

    await manager.releaseAll()

    #expect(
      Set(bookmarks.stoppedURLs()) == [
        URL(filePath: "/tmp/first"),
        URL(filePath: "/tmp/second"),
      ])
    #expect(await manager.activeURLs().isEmpty)
  }

  @Test("reports a repository load error without attempting bookmark resolution")
  func reportsRepositoryFailure() async {
    let manager = LibraryRootAccessManager(
      repository: FailingLibraryRootRepository(),
      bookmarkProvider: BookmarkProviderSpy()
    )

    let result = await manager.restore()

    #expect(result.restoredRoots.isEmpty)
    #expect(result.failures.isEmpty)
    #expect(result.repositoryError != nil)
  }

  @Test("registration failure releases the newly opened security scope")
  func failedRegistrationReleasesScope() async {
    let bookmarks = BookmarkProviderSpy()
    let manager = LibraryRootAccessManager(
      repository: FailingLibraryRootRepository(failOnRead: false),
      bookmarkProvider: bookmarks
    )
    let url = URL(filePath: "/tmp/photos")

    await #expect(throws: RootRepositoryError.failed) {
      try await manager.register(url: url)
    }

    #expect(bookmarks.stoppedURLs() == [url])
  }

  @Test("activeURL resolves by root id when pathHint differs from resolved path")
  func activeURLByRootIDDespitePathMismatch() async throws {
    let rootID = UUID()
    let original = LibraryRoot(
      id: rootID,
      displayName: "photos",
      pathHint: "/old/photos",
      bookmarkData: Data("bookmark".utf8),
      addedAt: .distantPast
    )
    let repository = InMemoryLibraryRootRepository(roots: [original])
    let bookmarks = BookmarkProviderStub(
      resolutions: [
        original.bookmarkData: ResolvedBookmark(
          url: URL(filePath: "/new/photos"),
          isStale: false
        )
      ]
    )
    let manager = LibraryRootAccessManager(
      repository: repository,
      bookmarkProvider: bookmarks
    )

    let result = await manager.restore()

    #expect(result.restoredRoots.map(\.url) == [URL(filePath: "/new/photos")])
    #expect(await manager.activeURL(for: rootID) == URL(filePath: "/new/photos"))
    #expect(await repository.libraryRoots().first?.pathHint == "/new/photos")
  }

  @Test("reactivate restores access for a previously registered root")
  func reactivateRestoresAccess() async throws {
    let repository = InMemoryLibraryRootRepository()
    let bookmarks = BookmarkProviderSpy()
    let manager = LibraryRootAccessManager(
      repository: repository,
      bookmarkProvider: bookmarks
    )
    let root = try await manager.register(url: URL(filePath: "/tmp/photos"))
    await manager.releaseAll()

    let url = try await manager.reactivate(rootID: root.id)

    #expect(url == URL(filePath: "/tmp/photos"))
    #expect(await manager.activeURL(for: root.id) == URL(filePath: "/tmp/photos"))
  }
}

private actor InMemoryLibraryRootRepository: LibraryRootRepository {
  private var roots: [UUID: LibraryRoot]

  init(roots: [LibraryRoot] = []) {
    self.roots = Dictionary(uniqueKeysWithValues: roots.map { ($0.id, $0) })
  }

  func libraryRoots() -> [LibraryRoot] {
    roots.values.sorted { $0.addedAt < $1.addedAt }
  }

  func upsertLibraryRoot(_ root: LibraryRoot) {
    roots[root.id] = root
  }

  func removeLibraryRoot(id: UUID) {
    roots[id] = nil
  }
}

private struct BookmarkProviderStub: BookmarkProviding {
  let resolutions: [Data: ResolvedBookmark]

  init(resolutions: [Data: ResolvedBookmark] = [:]) {
    self.resolutions = resolutions
  }

  func createBookmark(for url: URL) throws -> Data {
    Data("created:\(url.path)".utf8)
  }

  func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
    guard let resolution = resolutions[data] else {
      throw BookmarkStubError.missingResolution
    }
    return resolution
  }

  func startAccessing(_ url: URL) -> Bool {
    true
  }

  func stopAccessing(_ url: URL) {}
}

private final class BookmarkProviderSpy: BookmarkProviding, @unchecked Sendable {
  private let lock = NSLock()
  private var stopped: [URL] = []

  func createBookmark(for url: URL) throws -> Data {
    Data(url.path.utf8)
  }

  func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
    guard let path = String(data: data, encoding: .utf8) else {
      throw BookmarkStubError.missingResolution
    }
    return ResolvedBookmark(url: URL(filePath: path), isStale: false)
  }

  func startAccessing(_ url: URL) -> Bool {
    true
  }

  func stopAccessing(_ url: URL) {
    lock.lock()
    stopped.append(url)
    lock.unlock()
  }

  func stoppedURLs() -> [URL] {
    lock.lock()
    defer { lock.unlock() }
    return stopped
  }
}

private actor FailingLibraryRootRepository: LibraryRootRepository {
  private let failOnRead: Bool

  init(failOnRead: Bool = true) {
    self.failOnRead = failOnRead
  }

  func libraryRoots() throws -> [LibraryRoot] {
    if failOnRead {
      throw RootRepositoryError.failed
    }
    return []
  }

  func upsertLibraryRoot(_ root: LibraryRoot) throws {
    throw RootRepositoryError.failed
  }

  func removeLibraryRoot(id: UUID) throws {
    throw RootRepositoryError.failed
  }
}

private enum BookmarkStubError: Error {
  case missingResolution
}

private enum RootRepositoryError: Error {
  case failed
}
