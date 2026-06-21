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
  @Published private(set) var validationStatusMessage = "Validation idle"
  @Published private(set) var processingStatusMessage = "Processing idle"
  @Published var errorMessage: String?

  private let repository:
    any AssetRepository & AssetEnrichmentRepository & LibraryRootRepository
      & ProcessingHistoryRepository
  private let scanner: DirectoryScanner
  private let rootAccessManager: LibraryRootAccessManager
  private let enrichmentPipeline: ImageEnrichmentPipeline
  private let fileEventMonitor: LibraryRootFileEventMonitor
  private let validationScheduler: IndexValidationScheduler
  private let batchProcessor = ImageBatchProcessor()
  private let spotlightSource = SpotlightCandidateSource()

  init() {
    let dependencies = Self.makeDependencies()
    repository = dependencies.repository
    scanner = dependencies.scanner
    rootAccessManager = dependencies.rootAccessManager
    enrichmentPipeline = dependencies.enrichmentPipeline
    fileEventMonitor = dependencies.fileEventMonitor
    validationScheduler = dependencies.validationScheduler
    if let startupError = dependencies.startupError {
      errorMessage = startupError
      statusMessage = "Index persistence unavailable"
    }
    Task { [weak self] in
      await self?.fileEventMonitor.setDidScanHandler { [weak self] in
        await self?.refreshAfterFileEvents()
      }
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
      await startWatchingActiveRoots()
      await startBackgroundValidation()
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
      await startWatchingActiveRoots()
      await startBackgroundValidation()
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

  func filteredAssets(query: AssetQuery) -> [ImageAsset] {
    query.apply(to: assets, enrichments: enrichments)
  }

  func smartAssets(
    _ smartView: SmartAssetView,
    query: AssetQuery
  ) -> [ImageAsset] {
    query.apply(
      to: smartView.assets(in: assets),
      enrichments: enrichments
    )
  }

  func exportAssets(
    assetIDs: Set<AssetID>,
    to outputDirectory: URL
  ) async {
    let selectedAssets = assets.filter { assetIDs.contains($0.id) }
    guard !selectedAssets.isEmpty else {
      processingStatusMessage = "No images selected"
      return
    }
    processingStatusMessage = "Exporting \(selectedAssets.count) images…"
    do {
      let outputs = try await batchProcessor.process(
        ImageBatchRequest(
          assets: selectedAssets,
          outputDirectory: outputDirectory,
          format: .jpeg,
          compressionQuality: 0.85,
          filenameTemplate: "{name}"
        )
      )
      let records = outputs.map { output in
        ProcessingHistoryRecord(
          id: UUID(),
          sourceAssetID: output.sourceAssetID,
          operation: .export,
          outputURL: output.url,
          parameters: [
            "format": "jpeg",
            "compressionQuality": "0.85",
          ],
          createdAt: Date()
        )
      }
      try await repository.appendProcessingHistory(records)
      processingStatusMessage = "Exported \(outputs.count) images"
    } catch {
      processingStatusMessage = "Export failed"
      errorMessage = error.localizedDescription
    }
  }

  func validateLibraryNow() async {
    validationStatusMessage = "Validating indexed folders…"
    do {
      let summary = try await validationScheduler.validateNow(
        rootURLs: await rootAccessManager.activeURLs()
      )
      if let lastValidatedAt = summary.lastValidatedAt {
        validationStatusMessage =
          "Validated \(summary.validatedRootCount) folders · \(summary.failureCount) failed · \(lastValidatedAt.formatted())"
      } else {
        validationStatusMessage = "No active folders to validate"
      }
      assets = try await repository.assets()
      await enrichAccessibleAssets()
    } catch {
      validationStatusMessage = "Validation failed"
      errorMessage = error.localizedDescription
    }
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
      await startWatchingActiveRoots()
      await startBackgroundValidation()
      statusMessage = scanStatus(summary)
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Scan failed"
    }
    isScanning = false
    await enrichAccessibleAssets()
  }

  private func startWatchingActiveRoots() async {
    do {
      try await fileEventMonitor.start(rootURLs: await rootAccessManager.activeURLs())
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Folder watching unavailable"
    }
  }

  private func startBackgroundValidation() async {
    await validationScheduler.start(
      rootURLs: { [rootAccessManager] in
        await rootAccessManager.activeURLs()
      }
    )
    validationStatusMessage = "Background validation scheduled"
  }

  private func refreshAfterFileEvents() async {
    do {
      assets = try await repository.assets()
      enrichments = Dictionary(
        uniqueKeysWithValues: try await repository.enrichments()
          .map { ($0.assetID, $0) }
      )
      updateSimilarityGroups()
      statusMessage = "\(assets.count) images indexed · updated from disk"
      await enrichAccessibleAssets()
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Couldn’t refresh changed files"
    }
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
      let scanner = DirectoryScanner(repository: repository)
      return LibraryDependencies(
        repository: repository,
        scanner: scanner,
        rootAccessManager: LibraryRootAccessManager(repository: repository),
        enrichmentPipeline: ImageEnrichmentPipeline(
          repository: repository,
          enricher: ImageEnricher(cacheDirectory: thumbnailCacheURL)
        ),
        fileEventMonitor: LibraryRootFileEventMonitor(
          watcher: FSEventsFileEventWatcher(),
          scanner: scanner
        ),
        validationScheduler: IndexValidationScheduler(scanner: scanner),
        startupError: nil
      )
    } catch {
      let repository = InMemoryAssetRepository()
      let scanner = DirectoryScanner(repository: repository)
      return LibraryDependencies(
        repository: repository,
        scanner: scanner,
        rootAccessManager: LibraryRootAccessManager(repository: repository),
        enrichmentPipeline: ImageEnrichmentPipeline(
          repository: repository,
          enricher: ImageEnricher(
            cacheDirectory: FileManager.default.temporaryDirectory
              .appending(path: "Nivlo/Thumbnails", directoryHint: .isDirectory)
          )
        ),
        fileEventMonitor: LibraryRootFileEventMonitor(
          watcher: FSEventsFileEventWatcher(),
          scanner: scanner
        ),
        validationScheduler: IndexValidationScheduler(scanner: scanner),
        startupError: error.localizedDescription
      )
    }
  }
}

private struct LibraryDependencies {
  let repository:
    any AssetRepository & AssetEnrichmentRepository & LibraryRootRepository
      & ProcessingHistoryRepository
  let scanner: DirectoryScanner
  let rootAccessManager: LibraryRootAccessManager
  let enrichmentPipeline: ImageEnrichmentPipeline
  let fileEventMonitor: LibraryRootFileEventMonitor
  let validationScheduler: IndexValidationScheduler
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
