import Foundation
import NivloDomain
import Testing

@Suite("Asset media")
struct AssetMediaTests {
  @Test("classifies image and video content types")
  func classifiesMediaKind() {
    #expect(makeAsset(contentType: "public.png").mediaKind == .image)
    #expect(makeAsset(contentType: "public.mpeg-4").mediaKind == .video)
    #expect(makeAsset(contentType: "public.data").mediaKind == .unsupported)
  }

  @Test("clamps video trim ranges to a valid minimum duration")
  func clampsVideoTrimRange() {
    let range = VideoTrimRange(
      startSeconds: 9.8,
      endSeconds: 2,
      durationSeconds: 10,
      minimumDurationSeconds: 0.5
    )

    #expect(range.startSeconds == 9.5)
    #expect(range.endSeconds == 10)
  }
}

private func makeAsset(contentType: String) -> ImageAsset {
  ImageAsset(
    id: AssetID(volumeIdentifier: "volume", fileIdentifier: UUID().uuidString),
    url: URL(filePath: "/tmp/asset"),
    filename: "asset",
    contentType: contentType,
    fileSize: 1,
    createdAt: nil,
    modifiedAt: nil,
    pixelWidth: nil,
    pixelHeight: nil
  )
}
