import Foundation
import Testing

@testable import NivloIndexing

@Suite("Spotlight candidates")
struct SpotlightCandidateTests {
  @Test("maps indexed image metadata without reading the original file")
  func mapsMetadata() {
    let url = URL(filePath: "/Users/test/Pictures/cover.png")
    let modifiedAt = Date(timeIntervalSince1970: 1_700_000_000)

    let candidate = SpotlightCandidate(
      metadata: SpotlightCandidateMetadata(
        url: url,
        displayName: "cover.png",
        contentType: "public.png",
        fileSize: 2_048,
        pixelWidth: 1200,
        pixelHeight: 800,
        createdAt: nil,
        modifiedAt: modifiedAt
      )
    )

    #expect(candidate?.id == url.standardizedFileURL.path)
    #expect(candidate?.displayName == "cover.png")
    #expect(candidate?.contentType == "public.png")
    #expect(candidate?.fileSize == 2_048)
    #expect(candidate?.pixelWidth == 1200)
    #expect(candidate?.pixelHeight == 800)
    #expect(candidate?.modifiedAt == modifiedAt)
  }

  @Test("rejects metadata without a local file URL")
  func rejectsNonFileURL() {
    let candidate = SpotlightCandidate(
      metadata: SpotlightCandidateMetadata(
        url: URL(string: "https://example.com/image.png"),
        displayName: "image.png",
        contentType: "public.png",
        fileSize: nil,
        pixelWidth: nil,
        pixelHeight: nil,
        createdAt: nil,
        modifiedAt: nil
      )
    )

    #expect(candidate == nil)
  }

  @Test("uses the system image content-type tree and local computer scope")
  func queryConfiguration() {
    let configuration = SpotlightQueryConfiguration.images()

    #expect(configuration.imageContentType == "public.image")
    #expect(configuration.scopes == [NSMetadataQueryLocalComputerScope])
    #expect(configuration.resultLimit == 500)
  }
}
