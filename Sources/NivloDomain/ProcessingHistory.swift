import Foundation

public enum ProcessingOperation: String, Codable, Equatable, Sendable {
  case compress
  case convert
  case resize
  case rename
  case export
}

public struct ProcessingHistoryRecord: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let sourceAssetID: AssetID
  public let operation: ProcessingOperation
  public let outputURL: URL
  public let parameters: [String: String]
  public let createdAt: Date

  public init(
    id: UUID,
    sourceAssetID: AssetID,
    operation: ProcessingOperation,
    outputURL: URL,
    parameters: [String: String],
    createdAt: Date
  ) {
    self.id = id
    self.sourceAssetID = sourceAssetID
    self.operation = operation
    self.outputURL = outputURL
    self.parameters = parameters
    self.createdAt = createdAt
  }
}

public protocol ProcessingHistoryRepository: Sendable {
  func appendProcessingHistory(_ records: [ProcessingHistoryRecord]) async throws
  func processingHistory(for assetID: AssetID) async throws -> [ProcessingHistoryRecord]
}
