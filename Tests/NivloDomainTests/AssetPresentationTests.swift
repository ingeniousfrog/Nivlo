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
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
      pixelWidth: 1440,
      pixelHeight: 900
    )
    let enrichment = AssetEnrichment(
      assetID: asset.id,
      exactHash: "hash",
      perceptualHash: 42,
      thumbnailURL: URL(filePath: "/tmp/thumb.png"),
      exif: AssetEXIF(
        cameraMake: "Apple",
        cameraModel: "iPhone 15 Pro",
        lensModel: "Main Camera",
        capturedAt: Date(timeIntervalSince1970: 1_699_999_000),
        orientation: 1,
        isoSpeed: 200,
        focalLength: 24,
        aperture: 1.8,
        exposureTime: 1.0 / 120.0,
        keywords: ["hero", "banner"],
        dominantColors: ["#112233", "#445566"]
      ),
      indexedAt: Date(timeIntervalSince1970: 1_700_000_200)
    )

    let details = AssetPreviewDetails(asset: asset, enrichment: enrichment)

    #expect(details.filename == "Hero Image.png")
    #expect(details.format == "PNG")
    #expect(details.mediaKind == .image)
    #expect(details.dimensions == "1440 × 900")
    #expect(details.megapixels == "1.3 MP")
    #expect(details.aspectRatio == "8:5")
    #expect(details.fileSize == "1.5 MB")
    #expect(details.createdAt != nil)
    #expect(details.modifiedAt != nil)
    #expect(details.capturedAt != nil)
    #expect(details.camera == "Apple iPhone 15 Pro")
    #expect(details.lens == "Main Camera")
    #expect(details.exposure == "f/1.8 · 1/120s · ISO 200")
    #expect(details.dominantColors == ["#112233", "#445566"])
    #expect(details.keywords == ["hero", "banner"])
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
    #expect(details.dimensions == nil)
    #expect(details.megapixels == nil)
    #expect(details.aspectRatio == nil)
    #expect(details.fileSize == "400 bytes")
    #expect(details.camera == nil)
    #expect(details.exposure == nil)
  }

  @Test("formats video probe details for the preview panel")
  func formatsVideoPreviewDetails() {
    let asset = ImageAsset(
      id: AssetID(volumeIdentifier: "volume", fileIdentifier: "clip"),
      url: URL(filePath: "/Users/example/Movies/clip.mov"),
      filename: "clip.mov",
      contentType: "public.mpeg-4",
      fileSize: 12_400_000,
      createdAt: Date(timeIntervalSince1970: 1_700_000_000),
      modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
      pixelWidth: nil,
      pixelHeight: nil
    )
    let probe = VideoProbeInfo(
      durationSeconds: 83,
      width: 1_920,
      height: 1_080,
      frameRate: 29.97,
      hasAudio: true,
      videoCodec: "h264",
      audioCodec: "aac"
    )

    let details = AssetPreviewDetails(asset: asset, videoProbe: probe)

    #expect(details.mediaKind == .video)
    #expect(details.duration == "1:23")
    #expect(details.dimensions == "1920 × 1080")
    #expect(details.aspectRatio == "16:9")
    #expect(details.frameRate == "29.97 fps")
    #expect(details.hasAudio == true)
    #expect(details.videoCodec == "h264")
    #expect(details.audioCodec == "aac")
  }

  @Test("formats duration and frame rate titles")
  func formatsVideoTimingTitles() {
    #expect(AssetPreviewDetails.durationTitle(3_661) == "1:01:01")
    #expect(AssetPreviewDetails.durationTitle(65) == "1:05")
    #expect(AssetPreviewDetails.frameRateTitle(30) == "30 fps")
    #expect(AssetPreviewDetails.frameRateTitle(23.976) == "23.98 fps")
  }
}
