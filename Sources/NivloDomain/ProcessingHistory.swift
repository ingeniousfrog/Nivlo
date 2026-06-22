import Foundation

public enum DerivativeKind: String, Codable, Equatable, Sendable, CaseIterable {
  case original
  case edit
  case aiVariant
  case delivery
}

public enum ProcessingOperation: String, Codable, Equatable, Sendable {
  case compress
  case convert
  case resize
  case rename
  case export
  case edit
  case videoEdit
  case audioExtract
  case aiGenerate
}

public struct ProcessingHistoryRecord: Identifiable, Codable, Equatable, Sendable {
  public let id: UUID
  public let sourceAssetID: AssetID
  public let operation: ProcessingOperation
  public let outputURL: URL
  public let parameters: [String: String]
  public let createdAt: Date
  public let parentRecordID: UUID?
  public let derivativeKind: DerivativeKind

  public init(
    id: UUID,
    sourceAssetID: AssetID,
    operation: ProcessingOperation,
    outputURL: URL,
    parameters: [String: String],
    createdAt: Date,
    parentRecordID: UUID? = nil,
    derivativeKind: DerivativeKind = .delivery
  ) {
    self.id = id
    self.sourceAssetID = sourceAssetID
    self.operation = operation
    self.outputURL = outputURL
    self.parameters = parameters
    self.createdAt = createdAt
    self.parentRecordID = parentRecordID
    self.derivativeKind = derivativeKind
  }
}

public struct LineageNode: Identifiable, Equatable, Sendable {
  public let id: UUID
  public let record: ProcessingHistoryRecord

  public init(record: ProcessingHistoryRecord) {
    self.id = record.id
    self.record = record
  }
}

public struct LineageEdge: Equatable, Sendable {
  public let parentID: UUID
  public let childID: UUID

  public init(parentID: UUID, childID: UUID) {
    self.parentID = parentID
    self.childID = childID
  }
}

public struct AssetLineageGraph: Equatable, Sendable {
  public let assetID: AssetID
  public let nodes: [LineageNode]
  public let edges: [LineageEdge]

  public init(assetID: AssetID, records: [ProcessingHistoryRecord]) {
    self.assetID = assetID
    self.nodes = records.map(LineageNode.init(record:))
    self.edges = records.compactMap { record in
      guard let parentID = record.parentRecordID else {
        return nil
      }
      return LineageEdge(parentID: parentID, childID: record.id)
    }
  }
}

public protocol ProcessingHistoryRepository: Sendable {
  func appendProcessingHistory(_ records: [ProcessingHistoryRecord]) async throws
  func processingHistory(for assetID: AssetID) async throws -> [ProcessingHistoryRecord]
}

public enum AssetLineageBuilder {
  public static func graph(for assetID: AssetID, records: [ProcessingHistoryRecord]) -> AssetLineageGraph {
    AssetLineageGraph(assetID: assetID, records: records.sorted {
      if $0.createdAt != $1.createdAt {
        return $0.createdAt < $1.createdAt
      }
      return $0.id.uuidString < $1.id.uuidString
    })
  }
}
