import Foundation
import NivloDomain

public struct ExactDuplicateGroup: Identifiable, Equatable, Sendable {
  public let exactHash: String
  public let assetIDs: [AssetID]

  public var id: String {
    exactHash
  }

  public init(exactHash: String, assetIDs: [AssetID]) {
    self.exactHash = exactHash
    self.assetIDs = assetIDs
  }
}

public struct SimilarAssetGroup: Identifiable, Equatable, Sendable {
  public let assetIDs: [AssetID]

  public var id: String {
    assetIDs.map(Self.identityKey).joined(separator: "|")
  }

  public init(assetIDs: [AssetID]) {
    self.assetIDs = assetIDs
  }

  private static func identityKey(_ id: AssetID) -> String {
    "\(id.volumeIdentifier):\(id.fileIdentifier)"
  }
}

public enum AssetSimilarityAnalyzer {
  public static func exactDuplicateGroups(
    _ enrichments: [AssetEnrichment]
  ) -> [ExactDuplicateGroup] {
    Dictionary(grouping: enrichments, by: \.exactHash)
      .compactMap { exactHash, matches in
        guard matches.count > 1 else {
          return nil
        }
        return ExactDuplicateGroup(
          exactHash: exactHash,
          assetIDs: matches.map(\.assetID).sorted(by: identityOrder)
        )
      }
      .sorted { $0.exactHash < $1.exactHash }
  }

  public static func similarGroups(
    _ enrichments: [AssetEnrichment],
    maximumHammingDistance: Int = 8
  ) -> [SimilarAssetGroup] {
    guard enrichments.count > 1 else {
      return []
    }
    let distance = min(max(maximumHammingDistance, 0), 63)
    let sorted = enrichments.sorted {
      identityOrder($0.assetID, $1.assetID)
    }
    let candidatePairs = candidatePairs(
      hashes: sorted.map(\.perceptualHash),
      maximumHammingDistance: distance
    )
    let edges = candidatePairs.filter { pair in
      let first = sorted[pair.first]
      let second = sorted[pair.second]
      return first.exactHash != second.exactHash
        && (first.perceptualHash ^ second.perceptualHash).nonzeroBitCount
          <= distance
    }
    return connectedComponents(nodeCount: sorted.count, edges: edges)
      .filter { $0.count > 1 }
      .map { indexes in
        SimilarAssetGroup(
          assetIDs: indexes.map { sorted[$0].assetID }
        )
      }
      .sorted { first, second in
        guard let firstID = first.assetIDs.first,
          let secondID = second.assetIDs.first
        else {
          return first.assetIDs.count < second.assetIDs.count
        }
        return identityOrder(firstID, secondID)
      }
  }

  private static func candidatePairs(
    hashes: [UInt64],
    maximumHammingDistance: Int
  ) -> Set<IndexPair> {
    let segmentCount = maximumHammingDistance + 1
    let segments = hashSegments(count: segmentCount)
    var buckets: [SegmentKey: [Int]] = [:]
    for (index, hash) in hashes.enumerated() {
      for segment in segments {
        let key = SegmentKey(
          index: segment.index,
          value: segment.value(in: hash)
        )
        buckets[key, default: []].append(index)
      }
    }

    var pairs: Set<IndexPair> = []
    for indexes in buckets.values where indexes.count > 1 {
      for firstOffset in 0..<(indexes.count - 1) {
        for secondOffset in (firstOffset + 1)..<indexes.count {
          pairs.insert(
            IndexPair(
              first: indexes[firstOffset],
              second: indexes[secondOffset]
            )
          )
        }
      }
    }
    return pairs
  }

  private static func hashSegments(count: Int) -> [HashSegment] {
    let baseWidth = 64 / count
    let remainder = 64 % count
    var offset = 0
    return (0..<count).map { index in
      let width = baseWidth + (index < remainder ? 1 : 0)
      let segment = HashSegment(index: index, offset: offset, width: width)
      offset += width
      return segment
    }
  }

  private static func connectedComponents(
    nodeCount: Int,
    edges: Set<IndexPair>
  ) -> [[Int]] {
    var adjacency = Array(repeating: Set<Int>(), count: nodeCount)
    for edge in edges {
      adjacency[edge.first].insert(edge.second)
      adjacency[edge.second].insert(edge.first)
    }

    var remaining = Set(0..<nodeCount)
    var components: [[Int]] = []
    while let start = remaining.min() {
      var pending = [start]
      var component: Set<Int> = []
      while let node = pending.popLast() {
        guard !component.contains(node) else {
          continue
        }
        component.insert(node)
        pending.append(contentsOf: adjacency[node])
      }
      remaining.subtract(component)
      components.append(component.sorted())
    }
    return components
  }

  private static func identityOrder(_ first: AssetID, _ second: AssetID) -> Bool {
    if first.volumeIdentifier == second.volumeIdentifier {
      return first.fileIdentifier < second.fileIdentifier
    }
    return first.volumeIdentifier < second.volumeIdentifier
  }
}

private struct IndexPair: Hashable {
  let first: Int
  let second: Int
}

private struct SegmentKey: Hashable {
  let index: Int
  let value: UInt64
}

private struct HashSegment {
  let index: Int
  let offset: Int
  let width: Int

  func value(in hash: UInt64) -> UInt64 {
    let mask = UInt64.max >> (64 - width)
    return (hash >> offset) & mask
  }
}
