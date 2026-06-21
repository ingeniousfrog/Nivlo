import Foundation
import NivloDomain
import Testing

@testable import NivloPersistence

@Suite("SQLite processing history repository")
struct SQLiteProcessingHistoryRepositoryTests {
  @Test("persists processing history across repository instances")
  func persistsProcessingHistory() async throws {
    let databaseURL = temporaryDatabaseURL()
    let assetID = AssetID(volumeIdentifier: "volume", fileIdentifier: "file")
    let record = ProcessingHistoryRecord(
      id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
      sourceAssetID: assetID,
      operation: .resize,
      outputURL: URL(filePath: "/tmp/export.png"),
      parameters: ["maxPixelSize": "512"],
      createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    let writer = try SQLiteAssetRepository(databaseURL: databaseURL)
    try await writer.appendProcessingHistory([record])

    let reader = try SQLiteAssetRepository(databaseURL: databaseURL)
    let records = try await reader.processingHistory(for: assetID)

    #expect(records == [record])
  }
}

private func temporaryDatabaseURL() -> URL {
  FileManager.default.temporaryDirectory
    .appending(path: "\(UUID().uuidString).sqlite")
}
