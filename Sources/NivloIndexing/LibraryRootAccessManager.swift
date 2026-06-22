import Foundation
import NivloDomain

public struct ResolvedBookmark: Equatable, Sendable {
  public let url: URL
  public let isStale: Bool

  public init(url: URL, isStale: Bool) {
    self.url = url
    self.isStale = isStale
  }
}

public protocol BookmarkProviding: Sendable {
  func createBookmark(for url: URL) throws -> Data
  func resolveBookmark(_ data: Data) throws -> ResolvedBookmark
  func startAccessing(_ url: URL) -> Bool
  func stopAccessing(_ url: URL)
}

public struct FoundationBookmarkProvider: BookmarkProviding {
  public init() {}

  public func createBookmark(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  public func resolveBookmark(_ data: Data) throws -> ResolvedBookmark {
    var isStale = false
    let url = try URL(
      resolvingBookmarkData: data,
      options: [.withSecurityScope, .withoutUI],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
    return ResolvedBookmark(
      url: url.standardizedFileURL,
      isStale: isStale
    )
  }

  public func startAccessing(_ url: URL) -> Bool {
    url.startAccessingSecurityScopedResource()
  }

  public func stopAccessing(_ url: URL) {
    url.stopAccessingSecurityScopedResource()
  }
}

public struct ActiveLibraryRoot: Equatable, Sendable {
  public let root: LibraryRoot
  public let url: URL

  public init(root: LibraryRoot, url: URL) {
    self.root = root
    self.url = url
  }
}

public struct LibraryRootRestoreFailure: Equatable, Sendable {
  public let rootID: UUID
  public let message: String

  public init(rootID: UUID, message: String) {
    self.rootID = rootID
    self.message = message
  }
}

public struct LibraryRootRestoreResult: Equatable, Sendable {
  public let restoredRoots: [ActiveLibraryRoot]
  public let failures: [LibraryRootRestoreFailure]
  public let repositoryError: String?

  public init(
    restoredRoots: [ActiveLibraryRoot],
    failures: [LibraryRootRestoreFailure],
    repositoryError: String? = nil
  ) {
    self.restoredRoots = restoredRoots
    self.failures = failures
    self.repositoryError = repositoryError
  }
}

public actor LibraryRootAccessManager {
  private struct AccessRecord {
    let root: LibraryRoot
    let url: URL
    let startedSecurityScope: Bool
  }

  private let repository: any LibraryRootRepository
  private let bookmarkProvider: any BookmarkProviding
  private let now: @Sendable () -> Date
  private var activeRoots: [UUID: AccessRecord] = [:]

  public init(
    repository: any LibraryRootRepository,
    bookmarkProvider: any BookmarkProviding = FoundationBookmarkProvider(),
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.repository = repository
    self.bookmarkProvider = bookmarkProvider
    self.now = now
  }

  public func register(url: URL) async throws -> LibraryRoot {
    let url = url.standardizedFileURL
    let startedSecurityScope = bookmarkProvider.startAccessing(url)
    do {
      let existingRoot = try await repository.libraryRoots()
        .first { $0.pathHint == url.path }
      let root = LibraryRoot(
        id: existingRoot?.id ?? UUID(),
        displayName: url.lastPathComponent,
        pathHint: url.path,
        bookmarkData: try bookmarkProvider.createBookmark(for: url),
        addedAt: existingRoot?.addedAt ?? now()
      )
      try await repository.upsertLibraryRoot(root)
      replaceActiveRoot(
        root,
        url: url,
        startedSecurityScope: startedSecurityScope
      )
      return root
    } catch {
      if startedSecurityScope {
        bookmarkProvider.stopAccessing(url)
      }
      throw error
    }
  }

  public func restore() async -> LibraryRootRestoreResult {
    let roots: [LibraryRoot]
    do {
      roots = try await repository.libraryRoots()
    } catch {
      return LibraryRootRestoreResult(
        restoredRoots: [],
        failures: [],
        repositoryError: error.localizedDescription
      )
    }

    var restoredRoots: [ActiveLibraryRoot] = []
    var failures: [LibraryRootRestoreFailure] = []
    for root in roots {
      do {
        let resolved = try bookmarkProvider.resolveBookmark(root.bookmarkData)
        let activeRoot = try await activate(root, resolved: resolved)
        restoredRoots.append(activeRoot)
      } catch {
        failures.append(
          LibraryRootRestoreFailure(
            rootID: root.id,
            message: error.localizedDescription
          )
        )
      }
    }
    return LibraryRootRestoreResult(
      restoredRoots: restoredRoots,
      failures: failures
    )
  }

  public func activeURLs() -> [URL] {
    activeRoots.values
      .map(\.url)
      .sorted { $0.path < $1.path }
  }

  public func activeURL(for rootID: UUID) -> URL? {
    activeRoots[rootID]?.url
  }

  public func remove(rootID: UUID) async throws {
    try await repository.removeLibraryRoot(id: rootID)
    if let active = activeRoots.removeValue(forKey: rootID),
      active.startedSecurityScope
    {
      bookmarkProvider.stopAccessing(active.url)
    }
  }

  public func releaseAll() {
    for active in activeRoots.values where active.startedSecurityScope {
      bookmarkProvider.stopAccessing(active.url)
    }
    activeRoots = [:]
  }

  private func activate(
    _ root: LibraryRoot,
    resolved: ResolvedBookmark
  ) async throws -> ActiveLibraryRoot {
    let url = resolved.url.standardizedFileURL
    let startedSecurityScope = bookmarkProvider.startAccessing(url)
    do {
      let activeRoot: LibraryRoot
      let needsPathUpdate = url.path != root.pathHint
      if resolved.isStale || needsPathUpdate {
        activeRoot = LibraryRoot(
          id: root.id,
          displayName: url.lastPathComponent,
          pathHint: url.path,
          bookmarkData: resolved.isStale
            ? try bookmarkProvider.createBookmark(for: url)
            : root.bookmarkData,
          addedAt: root.addedAt
        )
        try await repository.upsertLibraryRoot(activeRoot)
      } else {
        activeRoot = root
      }
      replaceActiveRoot(
        activeRoot,
        url: url,
        startedSecurityScope: startedSecurityScope
      )
      return ActiveLibraryRoot(root: activeRoot, url: url)
    } catch {
      if startedSecurityScope {
        bookmarkProvider.stopAccessing(url)
      }
      throw error
    }
  }

  private func replaceActiveRoot(
    _ root: LibraryRoot,
    url: URL,
    startedSecurityScope: Bool
  ) {
    if let previous = activeRoots[root.id],
      previous.startedSecurityScope
    {
      bookmarkProvider.stopAccessing(previous.url)
    }
    activeRoots[root.id] = AccessRecord(
      root: root,
      url: url,
      startedSecurityScope: startedSecurityScope
    )
  }
}
