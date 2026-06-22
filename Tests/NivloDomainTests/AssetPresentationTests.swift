import Foundation
import Testing

@testable import NivloDomain

@Suite("Asset presentation")
struct AssetPresentationTests {
  @Test("formats asset details for the preview panel")
  func formatsPreviewDetails() {
    let asset = ImageAsset(
      id: AssetID(volumeIdentifier: "volume", fileIdentifier: "file"),
      url: URL(filePath: "/Users/example/Desktop/Hero Image.png"),
      filename: "Hero Image.png",
      contentType: "public.png",
      fileSize: 1_536_000,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      modifiedAt: nil,
      pixelWidth: 1440,
      pixelHeight: 900
    )

    let details = AssetPreviewDetails(asset: asset)

    #expect(details.title == "Hero Image.png")
    #expect(details.format == "PNG")
    #expect(details.dimensions == "1440 × 900")
    #expect(details.fileSize == "1.5 MB")
    #expect(details.path == "/Users/example/Desktop/Hero Image.png")
  }

  @Test("uses readable fallbacks for missing dimensions and unknown types")
  func formatsMissingPreviewDetails() {
    let asset = ImageAsset(
      id: AssetID(volumeIdentifier: "volume", fileIdentifier: "file"),
      url: URL(filePath: "/tmp/asset"),
      filename: "asset",
      contentType: "public.image",
      fileSize: 400,
      createdAt: nil,
      modifiedAt: nil,
      pixelWidth: nil,
      pixelHeight: nil
    )

    let details = AssetPreviewDetails(asset: asset)

    #expect(details.format == "IMAGE")
    #expect(details.dimensions == "Unknown")
    #expect(details.fileSize == "400 bytes")
  }
}
