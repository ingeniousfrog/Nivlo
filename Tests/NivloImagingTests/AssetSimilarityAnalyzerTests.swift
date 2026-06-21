import Foundation
import NivloDomain
import Testing

@testable import NivloImaging

@Suite("Asset similarity analyzer")
struct AssetSimilarityAnalyzerTests {
  @Test("groups assets with the same exact content hash")
  func exactDuplicates() {
    let first = analyzerEnrichment(fileID: "a", exactHash: "same", perceptualHash: 0)
    let second = analyzerEnrichment(fileID: "b", exactHash: "same", perceptualHash: 12)
    let unique = analyzerEnrichment(fileID: "c", exactHash: "unique", perceptualHash: 0)

    let groups = AssetSimilarityAnalyzer.exactDuplicateGroups(
      [unique, second, first]
    )

    #expect(groups.count == 1)
    #expect(groups.first?.exactHash == "same")
    #expect(groups.first?.assetIDs == [first.assetID, second.assetID])
  }

  @Test("groups perceptually close images with different exact hashes")
  func similarImages() {
    let first = analyzerEnrichment(
      fileID: "a",
      exactHash: "first",
      perceptualHash: 0b0000
    )
    let second = analyzerEnrichment(
      fileID: "b",
      exactHash: "second",
      perceptualHash: 0b0011
    )
    let distant = analyzerEnrichment(
      fileID: "c",
      exactHash: "third",
      perceptualHash: UInt64.max
    )

    let groups = AssetSimilarityAnalyzer.similarGroups(
      [distant, second, first],
      maximumHammingDistance: 2
    )

    #expect(groups.count == 1)
    #expect(groups.first?.assetIDs == [first.assetID, second.assetID])
  }

  @Test("keeps exact duplicates out of the similar-image view")
  func excludesExactDuplicatesFromSimilarGroups() {
    let first = analyzerEnrichment(
      fileID: "a",
      exactHash: "same",
      perceptualHash: 0
    )
    let second = analyzerEnrichment(
      fileID: "b",
      exactHash: "same",
      perceptualHash: 0
    )

    let groups = AssetSimilarityAnalyzer.similarGroups(
      [first, second],
      maximumHammingDistance: 8
    )

    #expect(groups.isEmpty)
  }

  @Test("uses connected components for chained similarity")
  func connectedSimilarityGroups() {
    let first = analyzerEnrichment(
      fileID: "a",
      exactHash: "first",
      perceptualHash: 0b0000
    )
    let middle = analyzerEnrichment(
      fileID: "b",
      exactHash: "middle",
      perceptualHash: 0b0011
    )
    let last = analyzerEnrichment(
      fileID: "c",
      exactHash: "last",
      perceptualHash: 0b1111
    )

    let groups = AssetSimilarityAnalyzer.similarGroups(
      [last, middle, first],
      maximumHammingDistance: 2
    )

    #expect(groups.count == 1)
    #expect(
      groups.first?.assetIDs == [
        first.assetID,
        middle.assetID,
        last.assetID,
      ])
  }
}

private func analyzerEnrichment(
  fileID: String,
  exactHash: String,
  perceptualHash: UInt64
) -> AssetEnrichment {
  AssetEnrichment(
    assetID: AssetID(volumeIdentifier: "volume", fileIdentifier: fileID),
    exactHash: exactHash,
    perceptualHash: perceptualHash,
    thumbnailURL: URL(filePath: "/tmp/\(fileID).jpg"),
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
    indexedAt: .distantPast
  )
}
