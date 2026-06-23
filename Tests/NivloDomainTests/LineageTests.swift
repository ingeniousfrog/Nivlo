import Foundation
import NivloDomain
import Testing

@Suite("Asset lineage builder")
struct AssetLineageTests {
  @Test("builds parent child edges")
  func buildsParentChildEdges() {
    let assetID = AssetID(volumeIdentifier: "vol", fileIdentifier: "file")
    let parentID = UUID(uuidString: "11111111-1111-1111-1111-111111111111")!
    let childID = UUID(uuidString: "22222222-2222-2222-2222-222222222222")!
    let records = [
      ProcessingHistoryRecord(
        id: parentID,
        sourceAssetID: assetID,
        operation: .edit,
        outputURL: URL(filePath: "/tmp/edit.webp"),
        parameters: ["tool": "picx"],
        createdAt: Date(timeIntervalSince1970: 10),
        derivativeKind: .edit
      ),
      ProcessingHistoryRecord(
        id: childID,
        sourceAssetID: assetID,
        operation: .rename,
        outputURL: URL(filePath: "/tmp/renamed.webp"),
        parameters: ["from": "edit.webp", "to": "renamed.webp"],
        createdAt: Date(timeIntervalSince1970: 20),
        parentRecordID: parentID,
        derivativeKind: .variant
      ),
    ]

    let graph = AssetLineageBuilder.graph(for: assetID, records: records)
    #expect(graph.nodes.count == 2)
    #expect(graph.edges == [LineageEdge(parentID: parentID, childID: childID)])
  }
}
