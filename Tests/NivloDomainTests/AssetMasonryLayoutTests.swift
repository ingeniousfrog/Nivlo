import Foundation
import NivloDomain
import Testing

@Suite("Asset masonry layout")
struct AssetMasonryLayoutTests {
  @Test("uses bounded source aspect ratios for display")
  func boundsDisplayAspectRatios() {
    #expect(makeAsset(id: "wide", width: 4_000, height: 1_000).displayAspectRatio == 2)
    #expect(makeAsset(id: "tall", width: 1_000, height: 4_000).displayAspectRatio == 0.5)
    #expect(makeAsset(id: "square", width: 1_000, height: 1_000).displayAspectRatio == 1)
    #expect(makeAsset(id: "unknown", width: nil, height: nil).displayAspectRatio == 4.0 / 3.0)
  }

  @Test("places each asset in the currently shortest column")
  func balancesColumns() {
    let assets = [
      makeAsset(id: "tall", width: 1_000, height: 2_000),
      makeAsset(id: "wide", width: 2_000, height: 1_000),
      makeAsset(id: "square", width: 1_000, height: 1_000),
    ]

    let columns = AssetMasonryLayout.columns(for: assets, columnCount: 2)

    #expect(
      columns.map { $0.map(\.id.fileIdentifier) } == [
        ["tall"],
        ["wide", "square"],
      ])
  }
}

private func makeAsset(
  id: String,
  width: Int?,
  height: Int?
) -> ImageAsset {
  ImageAsset(
    id: AssetID(volumeIdentifier: "volume", fileIdentifier: id),
    url: URL(filePath: "/tmp/\(id).png"),
    filename: "\(id).png",
    contentType: "public.png",
    fileSize: 1,
    createdAt: nil,
    modifiedAt: nil,
    pixelWidth: width,
    pixelHeight: height
  )
}
