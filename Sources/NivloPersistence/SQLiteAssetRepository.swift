import Foundation
import NivloDomain
import SQLite3

public enum SQLiteRepositoryError: Error, LocalizedError, Sendable {
  case openFailed(path: String, message: String)
  case statementFailed(sql: String, message: String)
  case executionFailed(sql: String, message: String)
  case invalidStoredPath(String)
  case invalidStoredEnrichment(String)

  public var errorDescription: String? {
    switch self {
    case .openFailed(let path, let message):
      "Could not open index at \(path): \(message)"
    case .statementFailed(let sql, let message):
      "Could not prepare index query '\(sql)': \(message)"
    case .executionFailed(let sql, let message):
      "Could not execute index query '\(sql)': \(message)"
    case .invalidStoredPath(let path):
      "The index contains an invalid file path: \(path)"
    case .invalidStoredEnrichment(let message):
      "The index contains invalid image enrichment data: \(message)"
    }
  }
}

public actor SQLiteAssetRepository:
  AssetRepository, AssetEnrichmentRepository, LibraryRootRepository,
  ProcessingHistoryRepository, IndexMaintenanceRepository
{
  private let connection: SQLiteConnection

  private var database: OpaquePointer {
    connection.handle
  }

  public init(databaseURL: URL) throws {
    try FileManager.default.createDirectory(
      at: databaseURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )

    var database: OpaquePointer?
    let result = sqlite3_open_v2(
      databaseURL.path,
      &database,
      SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
      nil
    )
    guard result == SQLITE_OK, let database else {
      let message =
        database.map { String(cString: sqlite3_errmsg($0)) }
        ?? "Unknown SQLite error"
      if let database {
        sqlite3_close(database)
      }
      throw SQLiteRepositoryError.openFailed(
        path: databaseURL.path,
        message: message
      )
    }

    do {
      try Self.configure(database)
      try Self.migrate(database)
    } catch {
      sqlite3_close(database)
      throw error
    }
    connection = SQLiteConnection(handle: database)
  }

  public func assets() throws -> [ImageAsset] {
    let sql = """
      SELECT volume_id, file_id, path, filename, content_type, file_size,
             created_at, modified_at, pixel_width, pixel_height
      FROM assets
      ORDER BY path ASC;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    var assets: [ImageAsset] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      assets.append(try decodeAsset(from: statement))
    }
    try requireFinished(statement, sql: sql)
    return assets
  }

  public func searchAssets(matching query: String) throws -> [ImageAsset] {
    let normalizedQuery = ftsQuery(query)
    guard !normalizedQuery.isEmpty else {
      return try assets()
    }
    let sql = """
      SELECT a.volume_id, a.file_id, a.path, a.filename, a.content_type,
             a.file_size, a.created_at, a.modified_at,
             a.pixel_width, a.pixel_height
      FROM asset_search_fts s
      JOIN assets a
        ON a.volume_id = s.volume_id
       AND a.file_id = s.file_id
      WHERE asset_search_fts MATCH ?
      ORDER BY rank, a.path ASC;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(normalizedQuery, at: 1, to: statement, sql: sql)

    var assets: [ImageAsset] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      assets.append(try decodeAsset(from: statement))
    }
    try requireFinished(statement, sql: sql)
    return assets
  }

  public func hiddenAssetPaths(in rootURL: URL) throws -> Set<String> {
    let rootPath = rootURL.standardizedFileURL.path
    let sql = """
      SELECT path
      FROM hidden_assets
      WHERE path = ? OR path LIKE ? ESCAPE char(92);
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(rootPath, at: 1, to: statement, sql: sql)
    try bind("\(escapeLikePattern(rootPath))/%", at: 2, to: statement, sql: sql)

    var paths: Set<String> = []
    while sqlite3_step(statement) == SQLITE_ROW {
      paths.insert(text(at: 0, from: statement))
    }
    try requireFinished(statement, sql: sql)
    return paths
  }

  public func hiddenAssets() throws -> [HiddenAssetRecord] {
    let sql = """
      SELECT h.path, h.hidden_at,
             m.volume_id, m.file_id, m.filename, m.content_type,
             m.file_size, m.created_at, m.modified_at,
             m.pixel_width, m.pixel_height
      FROM hidden_assets h
      LEFT JOIN hidden_asset_metadata m ON m.path = h.path
      ORDER BY h.hidden_at DESC, h.path ASC;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    var records: [HiddenAssetRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      let path = text(at: 0, from: statement)
      let url = URL(filePath: path)
      let asset: ImageAsset?
      if sqlite3_column_type(statement, 2) == SQLITE_NULL {
        asset = nil
      } else {
        asset = ImageAsset(
          id: AssetID(
            volumeIdentifier: text(at: 2, from: statement),
            fileIdentifier: text(at: 3, from: statement)
          ),
          url: url,
          filename: text(at: 4, from: statement),
          contentType: text(at: 5, from: statement),
          fileSize: sqlite3_column_int64(statement, 6),
          createdAt: date(at: 7, from: statement),
          modifiedAt: date(at: 8, from: statement),
          pixelWidth: integer(at: 9, from: statement),
          pixelHeight: integer(at: 10, from: statement)
        )
      }
      records.append(
        HiddenAssetRecord(
          url: url,
          hiddenAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 1)),
          asset: asset
        )
      )
    }
    try requireFinished(statement, sql: sql)
    return records
  }

  public func hideAsset(_ asset: ImageAsset) throws {
    let hiddenSQL = """
      INSERT OR REPLACE INTO hidden_assets(path, hidden_at)
      VALUES (?, ?);
      """
    let metadataSQL = """
      INSERT OR REPLACE INTO hidden_asset_metadata (
          path, volume_id, file_id, filename, content_type, file_size,
          created_at, modified_at, pixel_width, pixel_height
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      """
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
      let path = asset.url.standardizedFileURL.path
      let hiddenStatement = try prepare(hiddenSQL)
      defer { sqlite3_finalize(hiddenStatement) }
      try bind(path, at: 1, to: hiddenStatement, sql: hiddenSQL)
      sqlite3_bind_double(hiddenStatement, 2, Date().timeIntervalSince1970)
      try stepToCompletion(hiddenStatement, sql: hiddenSQL)

      let metadataStatement = try prepare(metadataSQL)
      defer { sqlite3_finalize(metadataStatement) }
      try bind(path, at: 1, to: metadataStatement, sql: metadataSQL)
      try bind(asset.id.volumeIdentifier, at: 2, to: metadataStatement, sql: metadataSQL)
      try bind(asset.id.fileIdentifier, at: 3, to: metadataStatement, sql: metadataSQL)
      try bind(asset.filename, at: 4, to: metadataStatement, sql: metadataSQL)
      try bind(asset.contentType, at: 5, to: metadataStatement, sql: metadataSQL)
      sqlite3_bind_int64(metadataStatement, 6, asset.fileSize)
      bind(asset.createdAt, at: 7, to: metadataStatement)
      bind(asset.modifiedAt, at: 8, to: metadataStatement)
      bind(asset.pixelWidth, at: 9, to: metadataStatement)
      bind(asset.pixelHeight, at: 10, to: metadataStatement)
      try stepToCompletion(metadataStatement, sql: metadataSQL)

      try deleteAssets(Set([asset.id]))
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  public func hideAsset(at url: URL) throws {
    let sql = """
      INSERT OR REPLACE INTO hidden_assets(path, hidden_at)
      VALUES (?, ?);
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(url.standardizedFileURL.path, at: 1, to: statement, sql: sql)
    sqlite3_bind_double(statement, 2, Date().timeIntervalSince1970)
    try stepToCompletion(statement, sql: sql)
  }

  public func unhideAsset(at url: URL) throws {
    let path = url.standardizedFileURL.path
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
      for table in ["hidden_asset_metadata", "hidden_assets"] {
        let sql = "DELETE FROM \(table) WHERE path = ?;"
        let statement = try prepare(sql)
        try bind(path, at: 1, to: statement, sql: sql)
        do {
          try stepToCompletion(statement, sql: sql)
          sqlite3_finalize(statement)
        } catch {
          sqlite3_finalize(statement)
          throw error
        }
      }
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  public func replaceAssets(
    in rootURL: URL,
    with assets: [ImageAsset]
  ) throws -> Int {
    try replaceAssets(in: rootURL, under: rootURL, with: assets)
  }

  public func replaceAssets(
    in scopeURL: URL,
    under rootURL: URL,
    with assets: [ImageAsset]
  ) throws -> Int {
    let visibleAssets = try filterHiddenAssets(assets, in: rootURL)
    let scopePath = scopeURL.standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
      let existingIDs = try assetIDs(inScopePath: scopePath, rootPath: rootPath)
      let replacementIDs = Set(visibleAssets.map(\.id))
      let removedIDs = existingIDs.subtracting(replacementIDs)
      try deleteAssets(removedIDs)
      try writeAssets(visibleAssets, rootPath: rootPath)
      try upsertSearchAssets(visibleAssets)
      try execute("COMMIT;")
      return removedIDs.count
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  public func upsertAssets(
    _ assets: [ImageAsset],
    in rootURL: URL
  ) throws {
    let visibleAssets = try filterHiddenAssets(assets, in: rootURL)
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
      try writeAssets(
        visibleAssets,
        rootPath: rootURL.standardizedFileURL.path
      )
      try upsertSearchAssets(visibleAssets)
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  public func libraryRoots() throws -> [LibraryRoot] {
    let sql = """
      SELECT id, display_name, path_hint, bookmark_data, added_at
      FROM library_roots
      ORDER BY added_at ASC, id ASC;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    var roots: [LibraryRoot] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      let idString = text(at: 0, from: statement)
      guard let id = UUID(uuidString: idString) else {
        throw SQLiteRepositoryError.executionFailed(
          sql: sql,
          message: "Invalid library root UUID: \(idString)"
        )
      }
      roots.append(
        LibraryRoot(
          id: id,
          displayName: text(at: 1, from: statement),
          pathHint: text(at: 2, from: statement),
          bookmarkData: data(at: 3, from: statement),
          addedAt: Date(
            timeIntervalSince1970: sqlite3_column_double(statement, 4)
          )
        )
      )
      result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: errorMessage
      )
    }
    return roots
  }

  public func upsertLibraryRoot(_ root: LibraryRoot) throws {
    let sql = """
      INSERT INTO library_roots (
          id, display_name, path_hint, bookmark_data, added_at
      ) VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
          display_name = excluded.display_name,
          path_hint = excluded.path_hint,
          bookmark_data = excluded.bookmark_data,
          added_at = excluded.added_at;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(root.id.uuidString, at: 1, to: statement, sql: sql)
    try bind(root.displayName, at: 2, to: statement, sql: sql)
    try bind(root.pathHint, at: 3, to: statement, sql: sql)
    try bind(root.bookmarkData, at: 4, to: statement, sql: sql)
    sqlite3_bind_double(statement, 5, root.addedAt.timeIntervalSince1970)
    try stepToCompletion(statement, sql: sql)
  }

  public func removeLibraryRoot(id: UUID) throws {
    let sql = "DELETE FROM library_roots WHERE id = ?;"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(id.uuidString, at: 1, to: statement, sql: sql)
    try stepToCompletion(statement, sql: sql)
  }

  public func appendProcessingHistory(
    _ records: [ProcessingHistoryRecord]
  ) throws {
    guard !records.isEmpty else {
      return
    }
    let sql = """
      INSERT INTO processing_history (
          id, volume_id, file_id, operation, output_path,
          parameters_json, created_at, parent_record_id, derivative_kind
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
          volume_id = excluded.volume_id,
          file_id = excluded.file_id,
          operation = excluded.operation,
          output_path = excluded.output_path,
          parameters_json = excluded.parameters_json,
          created_at = excluded.created_at,
          parent_record_id = excluded.parent_record_id,
          derivative_kind = excluded.derivative_kind;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
      for record in records {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bind(record.id.uuidString, at: 1, to: statement, sql: sql)
        try bind(record.sourceAssetID.volumeIdentifier, at: 2, to: statement, sql: sql)
        try bind(record.sourceAssetID.fileIdentifier, at: 3, to: statement, sql: sql)
        try bind(record.operation.rawValue, at: 4, to: statement, sql: sql)
        try bind(record.outputURL.standardizedFileURL.path, at: 5, to: statement, sql: sql)
        try bind(try JSONEncoder().encode(record.parameters), at: 6, to: statement, sql: sql)
        sqlite3_bind_double(statement, 7, record.createdAt.timeIntervalSince1970)
        if let parentRecordID = record.parentRecordID {
          try bind(parentRecordID.uuidString, at: 8, to: statement, sql: sql)
        } else {
          sqlite3_bind_null(statement, 8)
        }
        try bind(record.derivativeKind.rawValue, at: 9, to: statement, sql: sql)
        try stepToCompletion(statement, sql: sql)
      }
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  public func processingHistory(
    for assetID: AssetID
  ) throws -> [ProcessingHistoryRecord] {
    let sql = """
      SELECT id, volume_id, file_id, operation, output_path,
             parameters_json, created_at, parent_record_id, derivative_kind
      FROM processing_history
      WHERE volume_id = ? AND file_id = ?
      ORDER BY created_at ASC, id ASC;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(assetID.volumeIdentifier, at: 1, to: statement, sql: sql)
    try bind(assetID.fileIdentifier, at: 2, to: statement, sql: sql)

    var records: [ProcessingHistoryRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      records.append(try decodeProcessingHistory(from: statement, sql: sql))
    }
    try requireFinished(statement, sql: sql)
    return records
  }

  public func enrichments() throws -> [AssetEnrichment] {
    let sql = """
      SELECT volume_id, file_id, exact_hash, perceptual_hash,
             thumbnail_path, exif_json, indexed_at
      FROM asset_enrichments
      ORDER BY volume_id ASC, file_id ASC;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    var enrichments: [AssetEnrichment] = []
    var result = sqlite3_step(statement)
    while result == SQLITE_ROW {
      let hashText = text(at: 3, from: statement)
      guard let perceptualHash = UInt64(hashText, radix: 16) else {
        throw SQLiteRepositoryError.invalidStoredEnrichment(
          "Invalid perceptual hash: \(hashText)"
        )
      }
      let exifData = data(at: 5, from: statement)
      let exif: AssetEXIF
      do {
        exif = try JSONDecoder().decode(AssetEXIF.self, from: exifData)
      } catch {
        throw SQLiteRepositoryError.invalidStoredEnrichment(
          error.localizedDescription
        )
      }
      enrichments.append(
        AssetEnrichment(
          assetID: AssetID(
            volumeIdentifier: text(at: 0, from: statement),
            fileIdentifier: text(at: 1, from: statement)
          ),
          exactHash: text(at: 2, from: statement),
          perceptualHash: perceptualHash,
          thumbnailURL: URL(filePath: text(at: 4, from: statement)),
          exif: exif,
          indexedAt: Date(
            timeIntervalSince1970: sqlite3_column_double(statement, 6)
          )
        )
      )
      result = sqlite3_step(statement)
    }
    guard result == SQLITE_DONE else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: errorMessage
      )
    }
    return enrichments
  }

  public func upsertEnrichments(
    _ enrichments: [AssetEnrichment]
  ) throws {
    guard !enrichments.isEmpty else {
      return
    }
    let sql = """
      INSERT INTO asset_enrichments (
          volume_id, file_id, exact_hash, perceptual_hash,
          thumbnail_path, exif_json, indexed_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(volume_id, file_id) DO UPDATE SET
          exact_hash = excluded.exact_hash,
          perceptual_hash = excluded.perceptual_hash,
          thumbnail_path = excluded.thumbnail_path,
          exif_json = excluded.exif_json,
          indexed_at = excluded.indexed_at;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
      for enrichment in enrichments {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bind(
          enrichment.assetID.volumeIdentifier,
          at: 1,
          to: statement,
          sql: sql
        )
        try bind(
          enrichment.assetID.fileIdentifier,
          at: 2,
          to: statement,
          sql: sql
        )
        try bind(enrichment.exactHash, at: 3, to: statement, sql: sql)
        try bind(
          String(enrichment.perceptualHash, radix: 16),
          at: 4,
          to: statement,
          sql: sql
        )
        try bind(
          enrichment.thumbnailURL.standardizedFileURL.path,
          at: 5,
          to: statement,
          sql: sql
        )
        try bind(
          try JSONEncoder().encode(enrichment.exif),
          at: 6,
          to: statement,
          sql: sql
        )
        sqlite3_bind_double(
          statement,
          7,
          enrichment.indexedAt.timeIntervalSince1970
        )
        try stepToCompletion(statement, sql: sql)
        try upsertSearchEnrichment(enrichment)
      }
      let healthSQL = """
        UPDATE index_health
        SET last_successful_enrichment_at = ?, last_error_message = NULL
        WHERE id = 1;
        """
      let healthStatement = try prepare(healthSQL)
      sqlite3_bind_double(healthStatement, 1, Date().timeIntervalSince1970)
      do {
        try stepToCompletion(healthStatement, sql: healthSQL)
        sqlite3_finalize(healthStatement)
      } catch {
        sqlite3_finalize(healthStatement)
        throw error
      }
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  public func indexHealth() throws -> IndexHealthRecord {
    let sql = """
      SELECT last_successful_scan_at, last_successful_enrichment_at,
             last_error_message
      FROM index_health
      WHERE id = 1;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      try requireFinished(statement, sql: sql)
      return IndexHealthRecord()
    }
    return IndexHealthRecord(
      lastSuccessfulScanAt: date(at: 0, from: statement),
      lastSuccessfulEnrichmentAt: date(at: 1, from: statement),
      lastErrorMessage:
        sqlite3_column_type(statement, 2) == SQLITE_NULL
        ? nil : text(at: 2, from: statement)
    )
  }

  public func recordSuccessfulScan(at date: Date) throws {
    let sql = """
      UPDATE index_health
      SET last_successful_scan_at = ?, last_error_message = NULL
      WHERE id = 1;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_double(statement, 1, date.timeIntervalSince1970)
    try stepToCompletion(statement, sql: sql)
  }

  public func recordIndexError(_ message: String?) throws {
    let sql = """
      UPDATE index_health
      SET last_error_message = ?
      WHERE id = 1;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    if let message {
      try bind(message, at: 1, to: statement, sql: sql)
    } else {
      sqlite3_bind_null(statement, 1)
    }
    try stepToCompletion(statement, sql: sql)
  }

  public func enrichmentFailures() throws -> [EnrichmentFailureRecord] {
    let sql = """
      SELECT volume_id, file_id, message, failed_at
      FROM enrichment_failures
      ORDER BY failed_at DESC, volume_id ASC, file_id ASC;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    var failures: [EnrichmentFailureRecord] = []
    while sqlite3_step(statement) == SQLITE_ROW {
      failures.append(
        EnrichmentFailureRecord(
          assetID: AssetID(
            volumeIdentifier: text(at: 0, from: statement),
            fileIdentifier: text(at: 1, from: statement)
          ),
          message: text(at: 2, from: statement),
          failedAt: Date(
            timeIntervalSince1970: sqlite3_column_double(statement, 3)
          )
        )
      )
    }
    try requireFinished(statement, sql: sql)
    return failures
  }

  public func replaceEnrichmentFailures(
    _ failures: [EnrichmentFailureRecord]
  ) throws {
    let sql = """
      INSERT INTO enrichment_failures(volume_id, file_id, message, failed_at)
      VALUES (?, ?, ?, ?);
      """
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
      try execute("DELETE FROM enrichment_failures;")
      let statement = try prepare(sql)
      defer { sqlite3_finalize(statement) }
      for failure in failures {
        sqlite3_reset(statement)
        sqlite3_clear_bindings(statement)
        try bind(failure.assetID.volumeIdentifier, at: 1, to: statement, sql: sql)
        try bind(failure.assetID.fileIdentifier, at: 2, to: statement, sql: sql)
        try bind(failure.message, at: 3, to: statement, sql: sql)
        sqlite3_bind_double(statement, 4, failure.failedAt.timeIntervalSince1970)
        try stepToCompletion(statement, sql: sql)
      }
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  public func removeEnrichments(for assetIDs: Set<AssetID>) throws {
    guard !assetIDs.isEmpty else { return }
    let sql = """
      DELETE FROM asset_enrichments
      WHERE volume_id = ? AND file_id = ?;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    for assetID in assetIDs {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      try bind(assetID.volumeIdentifier, at: 1, to: statement, sql: sql)
      try bind(assetID.fileIdentifier, at: 2, to: statement, sql: sql)
      try stepToCompletion(statement, sql: sql)
    }
  }

  public func removeAllEnrichments() throws {
    try execute("DELETE FROM asset_enrichments;")
    try execute("DELETE FROM enrichment_failures;")
  }

  public func rebuildSearchIndex() throws {
    try execute("BEGIN IMMEDIATE TRANSACTION;")
    do {
      try execute("DELETE FROM asset_search_fts;")
      try upsertSearchAssets(assets())
      for enrichment in try enrichments() {
        try upsertSearchEnrichment(enrichment)
      }
      try execute("COMMIT;")
    } catch {
      try? execute("ROLLBACK;")
      throw error
    }
  }

  public func integrityCheck() throws -> String {
    let sql = "PRAGMA quick_check;"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    guard sqlite3_step(statement) == SQLITE_ROW else {
      try requireFinished(statement, sql: sql)
      return "unknown"
    }
    return text(at: 0, from: statement)
  }

  private func assetIDs(
    inScopePath scopePath: String,
    rootPath: String
  ) throws -> Set<AssetID> {
    let sql = """
      SELECT volume_id, file_id
      FROM assets
      WHERE root_path = ?
        AND (path = ? OR path LIKE ? ESCAPE char(92));
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(rootPath, at: 1, to: statement, sql: sql)
    try bind(scopePath, at: 2, to: statement, sql: sql)
    try bind("\(escapeLikePattern(scopePath))/%", at: 3, to: statement, sql: sql)

    var identities: Set<AssetID> = []
    while sqlite3_step(statement) == SQLITE_ROW {
      identities.insert(
        AssetID(
          volumeIdentifier: text(at: 0, from: statement),
          fileIdentifier: text(at: 1, from: statement)
        )
      )
    }
    try requireFinished(statement, sql: sql)
    return identities
  }

  private func escapeLikePattern(_ value: String) -> String {
    value
      .replacingOccurrences(of: "\\", with: "\\\\")
      .replacingOccurrences(of: "%", with: "\\%")
      .replacingOccurrences(of: "_", with: "\\_")
  }

  private func filterHiddenAssets(
    _ assets: [ImageAsset],
    in rootURL: URL
  ) throws -> [ImageAsset] {
    let hiddenPaths = try hiddenAssetPaths(in: rootURL)
    guard !hiddenPaths.isEmpty else {
      return assets
    }
    return assets.filter { !hiddenPaths.contains($0.url.standardizedFileURL.path) }
  }

  private func deleteAssets(_ identities: Set<AssetID>) throws {
    guard !identities.isEmpty else {
      return
    }
    let sql = "DELETE FROM assets WHERE volume_id = ? AND file_id = ?;"
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    for identity in identities {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      try bind(identity.volumeIdentifier, at: 1, to: statement, sql: sql)
      try bind(identity.fileIdentifier, at: 2, to: statement, sql: sql)
      try stepToCompletion(statement, sql: sql)
      try deleteSearchAsset(identity)
    }
  }

  private func upsertSearchAssets(_ assets: [ImageAsset]) throws {
    for asset in assets {
      try replaceSearchRow(assetID: asset.id) {
        [
          asset.filename,
          asset.url.path,
          asset.contentType,
          AssetSourceClassifier.classify(asset.url).rawValue,
        ]
        .joined(separator: " ")
      }
    }
  }

  private func upsertSearchEnrichment(_ enrichment: AssetEnrichment) throws {
    try upsertSearchRow(assetID: enrichment.assetID) {
      [
        enrichment.exif.cameraMake,
        enrichment.exif.cameraModel,
        enrichment.exif.lensModel,
        enrichment.exif.ocrText,
        enrichment.exif.keywords.joined(separator: " "),
        enrichment.exif.dominantColors.joined(separator: " "),
      ]
      .compactMap { $0 }
      .joined(separator: " ")
    }
  }

  private func upsertSearchRow(
    assetID: AssetID,
    text: () -> String
  ) throws {
    let existing = try searchText(for: assetID)
    let merged = [existing, text()]
      .compactMap { $0 }
      .joined(separator: " ")
    let sql = """
      INSERT INTO asset_search_fts(volume_id, file_id, text)
      VALUES (?, ?, ?);
      """
    try deleteSearchAsset(assetID)
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(assetID.volumeIdentifier, at: 1, to: statement, sql: sql)
    try bind(assetID.fileIdentifier, at: 2, to: statement, sql: sql)
    try bind(merged, at: 3, to: statement, sql: sql)
    try stepToCompletion(statement, sql: sql)
  }

  private func replaceSearchRow(
    assetID: AssetID,
    text: () -> String
  ) throws {
    let sql = """
      INSERT INTO asset_search_fts(volume_id, file_id, text)
      VALUES (?, ?, ?);
      """
    try deleteSearchAsset(assetID)
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(assetID.volumeIdentifier, at: 1, to: statement, sql: sql)
    try bind(assetID.fileIdentifier, at: 2, to: statement, sql: sql)
    try bind(text(), at: 3, to: statement, sql: sql)
    try stepToCompletion(statement, sql: sql)
  }

  private func searchText(for assetID: AssetID) throws -> String? {
    let sql = """
      SELECT text FROM asset_search_fts
      WHERE volume_id = ? AND file_id = ?
      LIMIT 1;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(assetID.volumeIdentifier, at: 1, to: statement, sql: sql)
    try bind(assetID.fileIdentifier, at: 2, to: statement, sql: sql)
    guard sqlite3_step(statement) == SQLITE_ROW else {
      try requireFinished(statement, sql: sql)
      return nil
    }
    return text(at: 0, from: statement)
  }

  private func deleteSearchAsset(_ assetID: AssetID) throws {
    let sql = """
      DELETE FROM asset_search_fts
      WHERE volume_id = ? AND file_id = ?;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }
    try bind(assetID.volumeIdentifier, at: 1, to: statement, sql: sql)
    try bind(assetID.fileIdentifier, at: 2, to: statement, sql: sql)
    try stepToCompletion(statement, sql: sql)
  }

  private func ftsQuery(_ query: String) -> String {
    query
      .split { !$0.isLetter && !$0.isNumber }
      .map { String($0) }
      .filter { !$0.isEmpty }
      .joined(separator: " ")
  }

  private func writeAssets(
    _ assets: [ImageAsset],
    rootPath: String
  ) throws {
    guard !assets.isEmpty else {
      return
    }
    let sql = """
      INSERT INTO assets (
          volume_id, file_id, root_path, path, filename, content_type,
          file_size, created_at, modified_at, pixel_width, pixel_height
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
      ON CONFLICT(volume_id, file_id) DO UPDATE SET
          root_path = excluded.root_path,
          path = excluded.path,
          filename = excluded.filename,
          content_type = excluded.content_type,
          file_size = excluded.file_size,
          created_at = excluded.created_at,
          modified_at = excluded.modified_at,
          pixel_width = excluded.pixel_width,
          pixel_height = excluded.pixel_height;
      """
    let statement = try prepare(sql)
    defer { sqlite3_finalize(statement) }

    for asset in assets {
      sqlite3_reset(statement)
      sqlite3_clear_bindings(statement)
      try bind(asset.id.volumeIdentifier, at: 1, to: statement, sql: sql)
      try bind(asset.id.fileIdentifier, at: 2, to: statement, sql: sql)
      try bind(rootPath, at: 3, to: statement, sql: sql)
      try bind(asset.url.standardizedFileURL.path, at: 4, to: statement, sql: sql)
      try bind(asset.filename, at: 5, to: statement, sql: sql)
      try bind(asset.contentType, at: 6, to: statement, sql: sql)
      sqlite3_bind_int64(statement, 7, asset.fileSize)
      bind(asset.createdAt, at: 8, to: statement)
      bind(asset.modifiedAt, at: 9, to: statement)
      bind(asset.pixelWidth, at: 10, to: statement)
      bind(asset.pixelHeight, at: 11, to: statement)
      try stepToCompletion(statement, sql: sql)
    }
  }

  private func decodeAsset(from statement: OpaquePointer) throws -> ImageAsset {
    let path = text(at: 2, from: statement)
    guard !path.isEmpty else {
      throw SQLiteRepositoryError.invalidStoredPath(path)
    }
    return ImageAsset(
      id: AssetID(
        volumeIdentifier: text(at: 0, from: statement),
        fileIdentifier: text(at: 1, from: statement)
      ),
      url: URL(filePath: path),
      filename: text(at: 3, from: statement),
      contentType: text(at: 4, from: statement),
      fileSize: sqlite3_column_int64(statement, 5),
      createdAt: date(at: 6, from: statement),
      modifiedAt: date(at: 7, from: statement),
      pixelWidth: integer(at: 8, from: statement),
      pixelHeight: integer(at: 9, from: statement)
    )
  }

  private func decodeProcessingHistory(
    from statement: OpaquePointer,
    sql: String
  ) throws -> ProcessingHistoryRecord {
    let idString = text(at: 0, from: statement)
    guard let id = UUID(uuidString: idString) else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: "Invalid processing history UUID: \(idString)"
      )
    }
    let operationText = text(at: 3, from: statement)
    guard let operation = ProcessingOperation(rawValue: operationText) else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: "Invalid processing operation: \(operationText)"
      )
    }
    let parameters = try JSONDecoder().decode(
      [String: String].self,
      from: data(at: 5, from: statement)
    )
    let parentRecordID: UUID?
    if sqlite3_column_type(statement, 7) == SQLITE_NULL {
      parentRecordID = nil
    } else {
      let parentIDString = text(at: 7, from: statement)
      parentRecordID = UUID(uuidString: parentIDString)
    }
    let derivativeKindText =
      sqlite3_column_type(statement, 8) == SQLITE_NULL
      ? DerivativeKind.delivery.rawValue
      : text(at: 8, from: statement)
    let derivativeKind = DerivativeKind(rawValue: derivativeKindText) ?? .delivery

    return ProcessingHistoryRecord(
      id: id,
      sourceAssetID: AssetID(
        volumeIdentifier: text(at: 1, from: statement),
        fileIdentifier: text(at: 2, from: statement)
      ),
      operation: operation,
      outputURL: URL(filePath: text(at: 4, from: statement)),
      parameters: parameters,
      createdAt: Date(timeIntervalSince1970: sqlite3_column_double(statement, 6)),
      parentRecordID: parentRecordID,
      derivativeKind: derivativeKind
    )
  }

  private func prepare(_ sql: String) throws -> OpaquePointer {
    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK,
      let statement
    else {
      throw SQLiteRepositoryError.statementFailed(
        sql: sql,
        message: errorMessage
      )
    }
    return statement
  }

  private func execute(_ sql: String) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: errorMessage
      )
    }
  }

  private func bind(
    _ value: String,
    at index: Int32,
    to statement: OpaquePointer,
    sql: String
  ) throws {
    guard
      sqlite3_bind_text(
        statement,
        index,
        value,
        -1,
        Self.sqliteTransient
      ) == SQLITE_OK
    else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: errorMessage
      )
    }
  }

  private func bind(
    _ value: Data,
    at index: Int32,
    to statement: OpaquePointer,
    sql: String
  ) throws {
    let result = value.withUnsafeBytes { bytes in
      sqlite3_bind_blob(
        statement,
        index,
        bytes.baseAddress,
        Int32(bytes.count),
        Self.sqliteTransient
      )
    }
    guard result == SQLITE_OK else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: errorMessage
      )
    }
  }

  private func bind(
    _ value: Date?,
    at index: Int32,
    to statement: OpaquePointer
  ) {
    if let value {
      sqlite3_bind_double(statement, index, value.timeIntervalSince1970)
    } else {
      sqlite3_bind_null(statement, index)
    }
  }

  private func bind(
    _ value: Int?,
    at index: Int32,
    to statement: OpaquePointer
  ) {
    if let value {
      sqlite3_bind_int64(statement, index, Int64(value))
    } else {
      sqlite3_bind_null(statement, index)
    }
  }

  private func text(
    at index: Int32,
    from statement: OpaquePointer
  ) -> String {
    guard let value = sqlite3_column_text(statement, index) else {
      return ""
    }
    return String(cString: value)
  }

  private func date(
    at index: Int32,
    from statement: OpaquePointer
  ) -> Date? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
      return nil
    }
    return Date(timeIntervalSince1970: sqlite3_column_double(statement, index))
  }

  private func data(
    at index: Int32,
    from statement: OpaquePointer
  ) -> Data {
    let byteCount = Int(sqlite3_column_bytes(statement, index))
    guard byteCount > 0, let bytes = sqlite3_column_blob(statement, index) else {
      return Data()
    }
    return Data(bytes: bytes, count: byteCount)
  }

  private func integer(
    at index: Int32,
    from statement: OpaquePointer
  ) -> Int? {
    guard sqlite3_column_type(statement, index) != SQLITE_NULL else {
      return nil
    }
    return Int(sqlite3_column_int64(statement, index))
  }

  private func stepToCompletion(
    _ statement: OpaquePointer,
    sql: String
  ) throws {
    guard sqlite3_step(statement) == SQLITE_DONE else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: errorMessage
      )
    }
  }

  private func requireFinished(
    _ statement: OpaquePointer,
    sql: String
  ) throws {
    guard
      sqlite3_errcode(database) == SQLITE_OK
        || sqlite3_errcode(database) == SQLITE_DONE
    else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: errorMessage
      )
    }
  }

  private var errorMessage: String {
    String(cString: sqlite3_errmsg(database))
  }

  private static let sqliteTransient = unsafeBitCast(
    -1,
    to: sqlite3_destructor_type.self
  )

  private static func configure(_ database: OpaquePointer) throws {
    try execute(
      database,
      sql: """
        PRAGMA journal_mode = WAL;
        PRAGMA foreign_keys = ON;
        PRAGMA synchronous = NORMAL;
        PRAGMA busy_timeout = 5000;
        """
    )
  }

  private static func migrate(_ database: OpaquePointer) throws {
    try execute(
      database,
      sql: """
        CREATE TABLE IF NOT EXISTS schema_migrations (
            version INTEGER PRIMARY KEY
        );

        CREATE TABLE IF NOT EXISTS assets (
            volume_id TEXT NOT NULL,
            file_id TEXT NOT NULL,
            root_path TEXT NOT NULL,
            path TEXT NOT NULL UNIQUE,
            filename TEXT NOT NULL,
            content_type TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            created_at REAL,
            modified_at REAL,
            pixel_width INTEGER,
            pixel_height INTEGER,
            PRIMARY KEY (volume_id, file_id)
        );

        CREATE INDEX IF NOT EXISTS assets_root_path_idx
        ON assets(root_path);

        CREATE TABLE IF NOT EXISTS hidden_assets (
            path TEXT PRIMARY KEY,
            hidden_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS hidden_asset_metadata (
            path TEXT PRIMARY KEY,
            volume_id TEXT NOT NULL,
            file_id TEXT NOT NULL,
            filename TEXT NOT NULL,
            content_type TEXT NOT NULL,
            file_size INTEGER NOT NULL,
            created_at REAL,
            modified_at REAL,
            pixel_width INTEGER,
            pixel_height INTEGER,
            FOREIGN KEY (path) REFERENCES hidden_assets(path) ON DELETE CASCADE
        );

        CREATE TABLE IF NOT EXISTS library_roots (
            id TEXT PRIMARY KEY,
            display_name TEXT NOT NULL,
            path_hint TEXT NOT NULL,
            bookmark_data BLOB NOT NULL,
            added_at REAL NOT NULL
        );

        CREATE TABLE IF NOT EXISTS asset_enrichments (
            volume_id TEXT NOT NULL,
            file_id TEXT NOT NULL,
            exact_hash TEXT NOT NULL,
            perceptual_hash TEXT NOT NULL,
            thumbnail_path TEXT NOT NULL,
            exif_json BLOB NOT NULL,
            indexed_at REAL NOT NULL,
            PRIMARY KEY (volume_id, file_id),
            FOREIGN KEY (volume_id, file_id)
              REFERENCES assets(volume_id, file_id)
              ON DELETE CASCADE
        );

        CREATE INDEX IF NOT EXISTS asset_enrichments_exact_hash_idx
        ON asset_enrichments(exact_hash);

        CREATE VIRTUAL TABLE IF NOT EXISTS asset_search_fts
        USING fts5(
            volume_id UNINDEXED,
            file_id UNINDEXED,
            text
        );

        CREATE TABLE IF NOT EXISTS processing_history (
            id TEXT PRIMARY KEY,
            volume_id TEXT NOT NULL,
            file_id TEXT NOT NULL,
            operation TEXT NOT NULL,
            output_path TEXT NOT NULL,
            parameters_json BLOB NOT NULL,
            created_at REAL NOT NULL
        );

        CREATE INDEX IF NOT EXISTS processing_history_asset_idx
        ON processing_history(volume_id, file_id, created_at);

        CREATE TRIGGER IF NOT EXISTS assets_invalidate_enrichment
        AFTER UPDATE OF file_size, modified_at ON assets
        WHEN OLD.file_size != NEW.file_size
          OR OLD.modified_at IS NOT NEW.modified_at
        BEGIN
          DELETE FROM asset_enrichments
          WHERE volume_id = NEW.volume_id
            AND file_id = NEW.file_id;
        END;

        INSERT OR IGNORE INTO schema_migrations(version) VALUES (1);
        INSERT OR IGNORE INTO schema_migrations(version) VALUES (2);
        INSERT OR IGNORE INTO schema_migrations(version) VALUES (3);
        INSERT OR IGNORE INTO schema_migrations(version) VALUES (4);
        INSERT OR IGNORE INTO schema_migrations(version) VALUES (5);
        INSERT OR IGNORE INTO schema_migrations(version) VALUES (6);
        INSERT OR IGNORE INTO schema_migrations(version) VALUES (7);
        """
    )
    try applyMigration8(database)
    try applyMigration9(database)
  }

  private static func applyMigration8(_ database: OpaquePointer) throws {
    guard !hasMigration(database, version: 8) else {
      return
    }
    try execute(
      database,
      sql: """
        ALTER TABLE processing_history
        ADD COLUMN parent_record_id TEXT;

        ALTER TABLE processing_history
        ADD COLUMN derivative_kind TEXT NOT NULL DEFAULT 'delivery';

        INSERT OR IGNORE INTO schema_migrations(version) VALUES (8);
        """
    )
  }

  private static func applyMigration9(_ database: OpaquePointer) throws {
    guard !hasMigration(database, version: 9) else {
      return
    }
    try execute(
      database,
      sql: """
        CREATE TABLE IF NOT EXISTS index_health (
            id INTEGER PRIMARY KEY CHECK (id = 1),
            last_successful_scan_at REAL,
            last_successful_enrichment_at REAL,
            last_error_message TEXT
        );

        INSERT OR IGNORE INTO index_health(id) VALUES (1);

        CREATE TABLE IF NOT EXISTS enrichment_failures (
            volume_id TEXT NOT NULL,
            file_id TEXT NOT NULL,
            message TEXT NOT NULL,
            failed_at REAL NOT NULL,
            PRIMARY KEY (volume_id, file_id)
        );

        INSERT OR IGNORE INTO schema_migrations(version) VALUES (9);
        """
    )
  }

  private static func hasMigration(_ database: OpaquePointer, version: Int) -> Bool {
    var statement: OpaquePointer?
    guard
      sqlite3_prepare_v2(
        database,
        "SELECT 1 FROM schema_migrations WHERE version = ? LIMIT 1;",
        -1,
        &statement,
        nil
      ) == SQLITE_OK,
      let statement
    else {
      return false
    }
    defer { sqlite3_finalize(statement) }
    sqlite3_bind_int(statement, 1, Int32(version))
    return sqlite3_step(statement) == SQLITE_ROW
  }

  private static func execute(
    _ database: OpaquePointer,
    sql: String
  ) throws {
    guard sqlite3_exec(database, sql, nil, nil, nil) == SQLITE_OK else {
      throw SQLiteRepositoryError.executionFailed(
        sql: sql,
        message: String(cString: sqlite3_errmsg(database))
      )
    }
  }
}

private final class SQLiteConnection: @unchecked Sendable {
  let handle: OpaquePointer

  init(handle: OpaquePointer) {
    self.handle = handle
  }

  deinit {
    sqlite3_close(handle)
  }
}
