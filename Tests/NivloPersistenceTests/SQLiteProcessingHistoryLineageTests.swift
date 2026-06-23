import Foundation
import NivloDomain
import Testing

@testable import NivloPersistence

@Suite("SQLite processing history lineage columns")
struct SQLiteProcessingHistoryLineageTests {
  @Test("persists parent record and derivative kind")
  func persistsLineageColumns() async throws {
    let databaseURL = temporaryDatabaseURL()
    let assetID = AssetID(volumeIdentifier: "volume", fileIdentifier: "file")
    let parentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let childID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let parent = ProcessingHistoryRecord(
      id: parentID,
      sourceAssetID: assetID,
      operation: .edit,
      outputURL: URL(filePath: "/tmp/edit.webp"),
      parameters: ["tool": "picx"],
      createdAt: Date(timeIntervalSince1970: 1),
      derivativeKind: .edit
    )
    let child = ProcessingHistoryRecord(
      id: childID,
      sourceAssetID: assetID,
      operation: .rename,
      outputURL: URL(filePath: "/tmp/renamed.webp"),
      parameters: ["from": "edit.webp", "to": "renamed.webp"],
      createdAt: Date(timeIntervalSince1970: 2),
      parentRecordID: parentID,
      derivativeKind: .variant
    )

    let writer = try SQLiteAssetRepository(databaseURL: databaseURL)
    try await writer.appendProcessingHistory([parent, child])

    let reader = try SQLiteAssetRepository(databaseURL: databaseURL)
    let records = try await reader.processingHistory(for: assetID)
    #expect(records == [parent, child])
  }
}

private func temporaryDatabaseURL() -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "\(UUID().uuidString).sqlite")
}
