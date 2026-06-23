import Foundation
import NivloDomain
import NivloImaging
import NivloIndexing
import NivloPersistence
import SQLite3
import UniformTypeIdentifiers

@main
struct NivloBenchmark {
  static func main() async throws {
    let requestedSizes = CommandLine.arguments.dropFirst().compactMap(Int.init)
    let sizes = requestedSizes.isEmpty ? [10_000, 50_000, 100_000] : requestedSizes
    print("assets,startup_ms,layout_ms,enrichment_ms,rescan_ms")
    for size in sizes {
      let assets = benchmarkAssets(count: size)
      let startup = try await benchmarkStartup(assets)
      let layout = benchmarkLayout(assets)
      let enrichment = try await benchmarkEnrichment(assets)
      let rescan = try await benchmarkRescan(count: size)
      print(
        [
          "\(size)",
          milliseconds(startup),
          milliseconds(layout),
          milliseconds(enrichment),
          milliseconds(rescan),
        ].joined(separator: ",")
      )
    }
  }

  private static func benchmarkStartup(
    _ assets: [ImageAsset]
  ) async throws -> Duration {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let databaseURL = directory.appending(path: "index.sqlite")
    _ = try SQLiteAssetRepository(databaseURL: databaseURL)
    try seedAssets(assets, databaseURL: databaseURL)
    let clock = ContinuousClock()
    let start = clock.now
    let reader = try SQLiteAssetRepository(databaseURL: databaseURL)
    _ = try await reader.assets()
    return start.duration(to: clock.now)
  }

  private static func benchmarkLayout(_ assets: [ImageAsset]) -> Duration {
    let clock = ContinuousClock()
    let start = clock.now
    _ = AssetMasonryLayout.columns(for: assets, columnCount: 6)
    return start.duration(to: clock.now)
  }

  private static func benchmarkEnrichment(
    _ assets: [ImageAsset]
  ) async throws -> Duration {
    let repository = BenchmarkEnrichmentRepository()
    let pipeline = ImageEnrichmentPipeline(
      repository: repository,
      enricher: BenchmarkEnricher(),
      maximumConcurrentTasks: 8
    )
    let clock = ContinuousClock()
    let start = clock.now
    _ = try await pipeline.enrich(assets)
    return start.duration(to: clock.now)
  }

  private static func benchmarkRescan(count: Int) async throws -> Duration {
    let rootURL = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
    let repository = InMemoryAssetRepository()
    let scanner = DirectoryScanner(
      repository: repository,
      contentLister: BenchmarkDirectoryLister(count: count),
      resourceReader: BenchmarkResourceReader()
    )
    let clock = ContinuousClock()
    let start = clock.now
    _ = try await scanner.scan(rootURL: rootURL)
    return start.duration(to: clock.now)
  }

  private static func benchmarkAssets(count: Int) -> [ImageAsset] {
    (0..<count).map { index in
      ImageAsset(
        id: AssetID(
          volumeIdentifier: "benchmark",
          fileIdentifier: "\(index)"
        ),
        url: URL(filePath: "/tmp/nivlo-benchmark-assets/\(index).png"),
        filename: "\(index).png",
        contentType: UTType.png.identifier,
        fileSize: Int64(100_000 + index),
        createdAt: nil,
        modifiedAt: Date(timeIntervalSince1970: Double(index)),
        pixelWidth: 1_000 + index % 1_000,
        pixelHeight: 800 + index % 500
      )
    }
  }

  private static func seedAssets(
    _ assets: [ImageAsset],
    databaseURL: URL
  ) throws {
    var database: OpaquePointer?
    guard
      sqlite3_open_v2(
        databaseURL.path,
        &database,
        SQLITE_OPEN_READWRITE,
        nil
      ) == SQLITE_OK,
      let database
    else {
      throw BenchmarkError.databaseOpenFailed
    }
    defer { sqlite3_close(database) }
    let sql = """
      INSERT INTO assets (
        volume_id, file_id, root_path, path, filename, content_type,
        file_size, created_at, modified_at, pixel_width, pixel_height
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else {
      throw BenchmarkError.statementFailed
    }
    defer { sqlite3_finalize(statement) }
    guard
      sqlite3_exec(database, "BEGIN IMMEDIATE TRANSACTION;", nil, nil, nil)
        == SQLITE_OK
    else {
      throw BenchmarkError.transactionFailed
    }
    do {
      for asset in assets {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bind(asset.id.volumeIdentifier, at: 1, to: statement)
        try bind(asset.id.fileIdentifier, at: 2, to: statement)
        try bind("/tmp/nivlo-benchmark-assets", at: 3, to: statement)
        try bind(asset.url.path, at: 4, to: statement)
        try bind(asset.filename, at: 5, to: statement)
        try bind(asset.contentType, at: 6, to: statement)
        guard sqlite3_bind_int64(statement, 7, asset.fileSize) == SQLITE_OK,
          sqlite3_bind_null(statement, 8) == SQLITE_OK,
          sqlite3_bind_double(
            statement,
            9,
            asset.modifiedAt?.timeIntervalSince1970 ?? 0
          ) == SQLITE_OK,
          sqlite3_bind_int64(statement, 10, Int64(asset.pixelWidth ?? 0)) == SQLITE_OK,
          sqlite3_bind_int64(statement, 11, Int64(asset.pixelHeight ?? 0)) == SQLITE_OK,
          sqlite3_step(statement) == SQLITE_DONE
        else {
          throw BenchmarkError.statementFailed
        }
      }
      guard sqlite3_exec(database, "COMMIT;", nil, nil, nil) == SQLITE_OK else {
        throw BenchmarkError.transactionFailed
      }
    } catch {
      sqlite3_exec(database, "ROLLBACK;", nil, nil, nil)
      throw error
    }
  }

  private static func bind(
    _ value: String,
    at index: Int32,
    to statement: OpaquePointer
  ) throws {
    let result = value.withCString {
      sqlite3_bind_text(statement, index, $0, -1, sqliteTransient)
    }
    guard result == SQLITE_OK else {
      throw BenchmarkError.statementFailed
    }
  }

  private static func milliseconds(_ duration: Duration) -> String {
    let components = duration.components
    let value =
      Double(components.seconds) * 1_000
      + Double(components.attoseconds) / 1_000_000_000_000_000
    return String(format: "%.2f", value)
  }
}

private let sqliteTransient = unsafeBitCast(
  -1,
  to: sqlite3_destructor_type.self
)

private enum BenchmarkError: Error {
  case databaseOpenFailed
  case statementFailed
  case transactionFailed
}

private struct BenchmarkDirectoryLister: DirectoryContentListing {
  let count: Int

  func contents(
    of rootURL: URL,
    resourceKeys _: [URLResourceKey]
  ) throws -> DirectoryListing {
    DirectoryListing(
      urls: (0..<count).map { rootURL.appending(path: "\($0).png") },
      issueCount: 0
    )
  }
}

private struct BenchmarkResourceReader: FileResourceReading {
  func snapshot(
    for url: URL,
    keys _: Set<URLResourceKey>
  ) throws -> FileResourceSnapshot {
    FileResourceSnapshot(
      isRegularFile: true,
      contentType: .png,
      fileSize: 100_000,
      createdAt: nil,
      modifiedAt: nil,
      fileIdentifier: url.deletingPathExtension().lastPathComponent,
      volumeIdentifier: "benchmark"
    )
  }
}

private struct BenchmarkEnricher: AssetImageEnriching {
  func enrich(_ asset: ImageAsset) async throws -> AssetEnrichment {
    AssetEnrichment(
      assetID: asset.id,
      exactHash: String(repeating: "a", count: 64),
      perceptualHash: UInt64(asset.id.fileIdentifier) ?? 0,
      thumbnailURL: URL(filePath: "/tmp/\(asset.id.fileIdentifier).jpg"),
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
}

private actor BenchmarkEnrichmentRepository: AssetEnrichmentRepository {
  private var stored: [AssetID: AssetEnrichment] = [:]

  func enrichments() -> [AssetEnrichment] {
    Array(stored.values)
  }

  func upsertEnrichments(_ enrichments: [AssetEnrichment]) {
    for enrichment in enrichments {
      stored[enrichment.assetID] = enrichment
    }
  }
}
