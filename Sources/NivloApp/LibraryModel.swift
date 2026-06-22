import AppKit
import Foundation
import NivloDomain
import NivloImaging
import NivloIndexing
import NivloPersistence
import UniformTypeIdentifiers

@MainActor
final class LibraryModel: ObservableObject {
  @Published private(set) var assets: [ImageAsset] = []
  @Published private(set) var hiddenAssets: [HiddenAssetRecord] = []
  @Published private(set) var roots: [LibraryRoot] = []
  @Published private(set) var enrichments: [AssetID: AssetEnrichment] = [:]
  @Published private(set) var duplicateGroups: [ExactDuplicateGroup] = []
  @Published private(set) var similarGroups: [SimilarAssetGroup] = []
  @Published private(set) var isScanning = false
  @Published private(set) var isEnriching = false
  @Published private(set) var statusMessage = "Choose a folder to begin."
  @Published private(set) var enrichmentStatusMessage = "Rich index pending"
  @Published private(set) var validationStatusMessage = "Validation idle"
  @Published private(set) var processingStatusMessage = "Processing idle"
  @Published private(set) var lineageByAssetID: [AssetID: AssetLineageGraph] = [:]
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
  let toolBootstrapper = ToolBootstrapper.shared

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
    toolBootstrapper.ensureToolsReady()
    do {
      let restoration = await rootAccessManager.restore()
      roots = try await repository.libraryRoots()
      assets = try await repository.assets()
      hiddenAssets = try await repository.hiddenAssets()
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
    var shouldEnrichAssets = false

    do {
      _ = try await rootAccessManager.register(url: rootURL)
      roots = try await repository.libraryRoots()
      await startWatchingActiveRoots()
      statusMessage = "Added \(rootURL.lastPathComponent) · scanning…"

      let summary = try await scanner.scan(rootURL: rootURL) { [weak self] progress in
        await self?.applyScanProgress(progress, folderName: rootURL.lastPathComponent)
      }
      assets = try await repository.assets()
      await startBackgroundValidation()
      statusMessage = scanStatus(summary)
      shouldEnrichAssets = true
    } catch {
      errorMessage = error.localizedDescription
      if roots.contains(where: { $0.pathHint == rootURL.standardizedFileURL.path }) {
        statusMessage = "Folder added · scan failed"
      } else {
        statusMessage = "Couldn’t add folder"
      }
    }
    isScanning = false
    if shouldEnrichAssets {
      await enrichAccessibleAssets()
    }
  }

  func rescan(_ root: LibraryRoot) async {
    guard let rootURL = await rootAccessManager.activeURL(for: root.id) else {
      errorMessage = "Access to \(root.displayName) is unavailable."
      return
    }
    await scanActiveRoot(rootURL)
  }

  func activeURL(for root: LibraryRoot) async -> URL? {
    await rootAccessManager.activeURL(for: root.id)
  }

  func revealRootInFinder(_ root: LibraryRoot) async {
    guard let url = await rootAccessManager.activeURL(for: root.id) else {
      errorMessage = "Access to \(root.displayName) is unavailable."
      return
    }
    NSWorkspace.shared.activateFileViewerSelecting([url])
  }

  func removeFolder(_ root: LibraryRoot) async {
    errorMessage = nil
    do {
      _ = try await repository.replaceAssets(
        in: URL(filePath: root.pathHint),
        with: []
      )
      try await rootAccessManager.remove(rootID: root.id)
      roots = try await repository.libraryRoots()
      assets = try await repository.assets()
      enrichments = Dictionary(
        uniqueKeysWithValues: try await repository.enrichments()
          .map { ($0.assetID, $0) }
      )
      updateSimilarityGroups()
      await startWatchingActiveRoots()
      await startBackgroundValidation()
      statusMessage = "\(assets.count) images indexed · removed \(root.displayName)"
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Couldn’t remove folder"
    }
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

  func lineage(for asset: ImageAsset) async -> AssetLineageGraph {
    if let cached = lineageByAssetID[asset.id] {
      return cached
    }
    do {
      let records = try await repository.processingHistory(for: asset.id)
      let graph = AssetLineageBuilder.graph(for: asset.id, records: records)
      lineageByAssetID[asset.id] = graph
      return graph
    } catch {
      return AssetLineageGraph(assetID: asset.id, records: [])
    }
  }

  func recordEditedImageExport(
    asset: ImageAsset,
    result: PicxOptimizeResult,
    request: ImageEditRequest,
    parentRecordID: UUID? = nil
  ) async {
    let record = ProcessingHistoryRecord(
      id: UUID(),
      sourceAssetID: asset.id,
      operation: .edit,
      outputURL: result.outputURL,
      parameters: [
        "tool": "picx",
        "format": request.format.rawValue,
        "quality": String(request.quality),
        "savingsRatio": String(format: "%.3f", result.savingsRatio),
        "originalSize": String(result.originalSize),
        "outputSize": String(result.outputSize),
      ],
      createdAt: Date(),
      parentRecordID: parentRecordID,
      derivativeKind: .edit
    )
    await appendHistoryRecords([record], assetID: asset.id)
  }

  func recordEditedVideoExport(
    asset: ImageAsset,
    outputURL: URL,
    request: VideoEditRequest,
    parentRecordID: UUID? = nil
  ) async {
    let operation: ProcessingOperation = request.extractAudioOnly ? .audioExtract : .videoEdit
    let record = ProcessingHistoryRecord(
      id: UUID(),
      sourceAssetID: asset.id,
      operation: operation,
      outputURL: outputURL,
      parameters: [
        "tool": "ffmpeg",
        "startSeconds": String(request.trimRange.startSeconds),
        "endSeconds": String(request.trimRange.endSeconds),
        "extractAudioOnly": request.extractAudioOnly ? "true" : "false",
        "outputFormat": request.outputFormat.rawValue,
      ],
      createdAt: Date(),
      parentRecordID: parentRecordID,
      derivativeKind: .delivery
    )
    await appendHistoryRecords([record], assetID: asset.id)
  }

  func recordAIGeneration(
    asset: ImageAsset,
    result: GenerationResult,
    parentRecordID: UUID? = nil
  ) async {
    let record = ProcessingHistoryRecord(
      id: UUID(),
      sourceAssetID: asset.id,
      operation: .aiGenerate,
      outputURL: result.outputURL,
      parameters: result.parameters.merging([
        "provider": result.providerID,
        "model": result.model,
      ]) { current, _ in current },
      createdAt: Date(),
      parentRecordID: parentRecordID,
      derivativeKind: .aiVariant
    )
    await appendHistoryRecords([record], assetID: asset.id)
  }

  private func appendHistoryRecords(
    _ records: [ProcessingHistoryRecord],
    assetID: AssetID
  ) async {
    do {
      try await repository.appendProcessingHistory(records)
      let updated = try await repository.processingHistory(for: assetID)
      lineageByAssetID[assetID] = AssetLineageBuilder.graph(
        for: assetID,
        records: updated
      )
      processingStatusMessage = "Recorded \(records.count) derivative(s)"
    } catch {
      errorMessage = error.localizedDescription
    }
  }

  func hideAsset(_ asset: ImageAsset) async {
    errorMessage = nil
    do {
      try await repository.hideAsset(asset)
      assets = try await repository.assets()
      hiddenAssets = try await repository.hiddenAssets()
      enrichments = Dictionary(
        uniqueKeysWithValues: try await repository.enrichments()
          .map { ($0.assetID, $0) }
      )
      updateSimilarityGroups()
      statusMessage = "\(assets.count) images indexed · hidden \(asset.filename)"
    } catch {
      errorMessage = error.localizedDescription
      statusMessage = "Couldn’t hide asset"
    }
  }

  func unhideAsset(_ record: HiddenAssetRecord) async -> String? {
    guard !isScanning else {
      errorMessage = "Wait for the current folder scan to finish, then try again."
      statusMessage = "Couldn’t restore asset while scanning"
      return nil
    }
    errorMessage = nil
    let activeRoots = await rootAccessManager.activeURLs()
    guard
      FileManager.default.fileExists(atPath: record.url.path),
      let root =
        activeRoots
        .filter({ record.url.isContained(in: $0) })
        .max(by: { $0.path.count < $1.path.count })
    else {
      errorMessage =
        "The original file or its indexed folder is unavailable. Reconnect the drive or add the folder again."
      statusMessage = "Couldn’t restore hidden asset"
      return nil
    }

    isScanning = true
    statusMessage = "Restoring \(record.url.lastPathComponent)…"
    do {
      try await repository.unhideAsset(at: record.url)
      _ = try await scanner.scan(
        scopeURL: record.url.deletingLastPathComponent(),
        under: root
      )
      assets = try await repository.assets()
      guard
        assets.contains(where: {
          $0.url.standardizedFileURL == record.url.standardizedFileURL
        })
      else {
        throw LibraryModelError.restoredAssetMissing(record.url)
      }
      hiddenAssets = try await repository.hiddenAssets()
      enrichments = Dictionary(
        uniqueKeysWithValues: try await repository.enrichments()
          .map { ($0.assetID, $0) }
      )
      updateSimilarityGroups()
      isScanning = false
      statusMessage = "\(assets.count) images indexed · restored \(record.url.lastPathComponent)"
      await enrichAccessibleAssets()
      return root.standardizedFileURL.path
    } catch {
      if let asset = record.asset {
        try? await repository.hideAsset(asset)
      } else {
        try? await repository.hideAsset(at: record.url)
      }
      assets = (try? await repository.assets()) ?? assets
      hiddenAssets = (try? await repository.hiddenAssets()) ?? hiddenAssets
      isScanning = false
      errorMessage = error.localizedDescription
      statusMessage = "Couldn’t restore hidden asset"
      return nil
    }
  }

  func validateLibraryNow() async {
    guard !isScanning else {
      return
    }
    isScanning = true
    defer { isScanning = false }
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

  private func applyScanProgress(
    _ progress: ScanProgress,
    folderName: String
  ) async {
    assets = (try? await repository.assets()) ?? assets
    statusMessage =
      "Scanning \(folderName) · \(progress.indexedCount) / \(progress.discoveredCount)"
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
    validationStatusMessage = "Automatic refresh ready"
  }

  private func refreshAfterFileEvents() async {
    do {
      assets = try await repository.assets()
      hiddenAssets = try await repository.hiddenAssets()
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
        asset.isRasterImage
          && activeRoots.contains { root in
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

extension ImageAsset {
  fileprivate var isRasterImage: Bool {
    UTType(contentType)?.conforms(to: .image) == true
  }
}

private enum LibraryModelError: Error, LocalizedError {
  case applicationSupportUnavailable
  case restoredAssetMissing(URL)

  var errorDescription: String? {
    switch self {
    case .applicationSupportUnavailable:
      "The macOS Application Support directory is unavailable."
    case .restoredAssetMissing(let url):
      "Nivlo could not add \(url.lastPathComponent) back to the index."
    }
  }
}
