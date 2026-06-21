import Foundation
import NivloDomain
import NivloImaging
import NivloIndexing
import NivloPersistence

@MainActor
final class LibraryModel: ObservableObject {
  @Published private(set) var assets: [ImageAsset] = []
  @Published private(set) var roots: [LibraryRoot] = []
  @Published private(set) var spotlightCandidates: [SpotlightCandidate] = []
  @Published private(set) var enrichments: [AssetID: AssetEnrichment] = [:]
  @Published private(set) var duplicateGroups: [ExactDuplicateGroup] = []
  @Published private(set) var similarGroups: [SimilarAssetGroup] = []
  @Published private(set) var isScanning = false
  @Published private(set) var isEnriching = false
  @Published private(set) var isDiscoveringSpotlight = false
  @Published private(set) var statusMessage = "Choose a folder to begin."
  @Published private(set) var enrichmentStatusMessage = "Rich index pending"
  @Published private(set) var spotlightStatusMessage = "Checking Spotlight…"
  @Published var errorMessage: String?

  private let repository: any AssetRepository & AssetEnrichmentRepository & LibraryRootRepository
  private let scanner: DirectoryScanner
  private let rootAccessManager: LibraryRootAccessManager
  private let enrichmentPipeline: ImageEnrichmentPipeline
  private let spotlightSource = SpotlightCandidateSource()

  init() {
    let dependencies = Self.makeDependencies()
    repository = dependencies.repository
    scanner = dependencies.scanner
    rootAccessManager = dependencies.rootAccessManager
    enrichmentPipeline = dependencies.enrichmentPipeline
    if let startupError = dependencies.startupError {
      errorMessage = startupError
      statusMessage = "Index persistence unavailable"
    }
  }

  func loadLibrary() async {
    do {
      let restoration = await rootAccessManager.restore()
      roots = try await repository.libraryRoots()
      assets = try await repository.assets()
      enrichments = Dictionary(
        uniqueKeysWithValues: try await repository.enrichments()
          .map { ($0.assetID, $0) }
      )
      updateSimilarityGroups()
      if let repositoryError = restoration.repositoryError {
        errorMessage = repositoryError
        statusMessage = "Couldn’t restore folder access"
      } else if !restoration.failures.isEmpty {
        statusMessage =
          "\(assets.count) images indexed · \(restoration.failures.count) folder unavailable"
      } else if assets.isEmpty {
        statusMessage = "Choose a folder to begin."
      } else {
        statusMessage = "\(assets.count) images indexed"
      }
      await enrichAccessibleAssets()
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Couldn’t load the index"
    }
  }

  func addFolder(_ rootURL: URL) async {
    guard !isScanning else {
      return
    }
    isScanning = true
    errorMessage = nil
    statusMessage = "Scanning \(rootURL.lastPathComponent)…"

    do {
      _ = try await rootAccessManager.register(url: rootURL)
      let summary = try await scanner.scan(rootURL: rootURL)
      roots = try await repository.libraryRoots()
      assets = try await repository.assets()
      statusMessage = scanStatus(summary)
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Scan failed"
    }
    isScanning = false
    await enrichAccessibleAssets()
  }

  func discoverSpotlightCandidates() async {
    guard !isDiscoveringSpotlight else {
      return
    }
    isDiscoveringSpotlight = true
    spotlightStatusMessage = "Checking Spotlight…"
    do {
      spotlightCandidates = try await spotlightSource.discover()
      spotlightStatusMessage =
        spotlightCandidates.isEmpty
        ? "No Spotlight candidates"
        : "\(spotlightCandidates.count) quick candidates"
    } catch {
      spotlightStatusMessage = "Spotlight unavailable"
    }
    isDiscoveringSpotlight = false
  }

  func rescan(_ root: LibraryRoot) async {
    guard
      let rootURL = await rootAccessManager.activeURLs()
        .first(where: { $0.path == root.pathHint })
    else {
      errorMessage = "Access to \(root.displayName) is unavailable."
      return
    }
    await scanActiveRoot(rootURL)
  }

  private func scanActiveRoot(_ rootURL: URL) async {
    guard !isScanning else {
      return
    }
    isScanning = true
    errorMessage = nil
    statusMessage = "Scanning \(rootURL.lastPathComponent)…"
    do {
      let summary = try await scanner.scan(rootURL: rootURL)
      assets = try await repository.assets()
      statusMessage = scanStatus(summary)
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Scan failed"
    }
    isScanning = false
    await enrichAccessibleAssets()
  }

  private func enrichAccessibleAssets() async {
    guard !isEnriching else {
      return
    }
    isEnriching = true
    enrichmentStatusMessage = "Building thumbnails and fingerprints…"
    do {
      let activeRoots = await rootAccessManager.activeURLs()
      let accessibleAssets = assets.filter { asset in
        activeRoots.contains { root in
          asset.url.isContained(in: root)
        }
      }
      let summary = try await enrichmentPipeline.enrich(accessibleAssets)
      enrichments = Dictionary(
        uniqueKeysWithValues: try await repository.enrichments()
          .map { ($0.assetID, $0) }
      )
      updateSimilarityGroups()
      enrichmentStatusMessage =
        summary.failures.isEmpty
        ? "\(enrichments.count) thumbnails and fingerprints ready"
        : "\(summary.completedCount) enriched · \(summary.failures.count) failed"
    } catch {
      enrichmentStatusMessage = "Rich indexing failed"
    }
    isEnriching = false
  }

  private func updateSimilarityGroups() {
    let values = Array(enrichments.values)
    duplicateGroups = AssetSimilarityAnalyzer.exactDuplicateGroups(values)
    similarGroups = AssetSimilarityAnalyzer.similarGroups(values)
  }

  private func scanStatus(_ summary: ScanSummary) -> String {
    if summary.issueCount > 0 {
      return
        "\(summary.indexedCount) images updated · \(summary.issueCount) scan issue"
    }
    return "\(summary.indexedCount) images indexed"
  }

  private static func databaseURL() throws -> URL {
    try applicationSupportURL().appending(path: "index.sqlite")
  }

  private static func thumbnailCacheURL() throws -> URL {
    try applicationSupportURL()
      .appending(path: "Thumbnails", directoryHint: .isDirectory)
  }

  private static func applicationSupportURL() throws -> URL {
    guard
      let applicationSupportURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      throw LibraryModelError.applicationSupportUnavailable
    }
    return
      applicationSupportURL
      .appending(path: "Nivlo", directoryHint: .isDirectory)
  }

  private static func makeDependencies() -> LibraryDependencies {
    do {
      let databaseURL = try databaseURL()
      let thumbnailCacheURL = try thumbnailCacheURL()
      let repository = try SQLiteAssetRepository(databaseURL: databaseURL)
      return LibraryDependencies(
        repository: repository,
        scanner: DirectoryScanner(repository: repository),
        rootAccessManager: LibraryRootAccessManager(repository: repository),
        enrichmentPipeline: ImageEnrichmentPipeline(
          repository: repository,
          enricher: ImageEnricher(cacheDirectory: thumbnailCacheURL)
        ),
        startupError: nil
      )
    } catch {
      let repository = InMemoryAssetRepository()
      return LibraryDependencies(
        repository: repository,
        scanner: DirectoryScanner(repository: repository),
        rootAccessManager: LibraryRootAccessManager(repository: repository),
        enrichmentPipeline: ImageEnrichmentPipeline(
          repository: repository,
          enricher: ImageEnricher(
            cacheDirectory: FileManager.default.temporaryDirectory
              .appending(path: "Nivlo/Thumbnails", directoryHint: .isDirectory)
          )
        ),
        startupError: error.localizedDescription
      )
    }
  }
}

private struct LibraryDependencies {
  let repository: any AssetRepository & AssetEnrichmentRepository & LibraryRootRepository
  let scanner: DirectoryScanner
  let rootAccessManager: LibraryRootAccessManager
  let enrichmentPipeline: ImageEnrichmentPipeline
  let startupError: String?
}

extension URL {
  fileprivate func isContained(in rootURL: URL) -> Bool {
    let candidatePath = standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path
    return candidatePath == rootPath
      || candidatePath.hasPrefix(rootPath + "/")
  }
}

private enum LibraryModelError: Error, LocalizedError {
  case applicationSupportUnavailable

  var errorDescription: String? {
    "The macOS Application Support directory is unavailable."
  }
}
