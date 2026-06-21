import Foundation
import Testing

@testable import NivloDomain

@Suite("Asset query")
struct AssetQueryTests {
  @Test("decodes older EXIF payloads that do not include rich index fields")
  func decodesLegacyEXIFPayloads() throws {
    let data = Data(
      """
      {
        "cameraMake": "Nivlo",
        "cameraModel": null,
        "lensModel": null,
        "capturedAt": null,
        "orientation": 1,
        "isoSpeed": null,
        "focalLength": null,
        "aperture": null,
        "exposureTime": null
      }
      """.utf8
    )

    let exif = try JSONDecoder().decode(AssetEXIF.self, from: data)

    #expect(exif.cameraMake == "Nivlo")
    #expect(exif.keywords.isEmpty)
    #expect(exif.dominantColors.isEmpty)
  }

  @Test("matches filename path format and OCR text")
  func matchesTextFields() {
    let asset = makeAsset(
      filename: "hero.png",
      url: URL(filePath: "/tmp/project/assets/hero.png"),
      contentType: "public.png"
    )
    let result = AssetQuery(searchText: "project hero png")
      .apply(to: [asset], enrichments: [asset.id: makeEnrichment(assetID: asset.id)])

    #expect(result == [asset])
  }

  @Test("filters by size format dimensions and folder")
  func filtersByMetadata() {
    let matching = makeAsset(
      filename: "large.jpg",
      url: URL(filePath: "/tmp/library/photos/large.jpg"),
      contentType: "public.jpeg",
      fileSize: 5_000,
      pixelWidth: 2000,
      pixelHeight: 1200
    )
    let small = makeAsset(
      filename: "small.jpg",
      url: URL(filePath: "/tmp/library/photos/small.jpg"),
      contentType: "public.jpeg",
      fileSize: 500,
      pixelWidth: 200,
      pixelHeight: 120
    )
    let query = AssetQuery(
      folders: [URL(filePath: "/tmp/library/photos")],
      contentTypes: ["public.jpeg"],
      minimumFileSize: 1_000,
      minimumPixelWidth: 1_000
    )

    let result = query.apply(to: [matching, small], enrichments: [:])

    #expect(result == [matching])
  }

  @Test("classifies common source locations")
  func classifiesSourceLocations() {
    #expect(
      AssetSourceClassifier.classify(
        URL(filePath: "/Users/example/Downloads/asset.png")
      ) == .downloads
    )
    #expect(
      AssetSourceClassifier.classify(
        URL(filePath: "/Users/example/Desktop/asset.png")
      ) == .desktop
    )
    #expect(
      AssetSourceClassifier.classify(
        URL(filePath: "/Volumes/External/project/asset.png")
      ) == .externalVolume
    )
    #expect(
      AssetSourceClassifier.classify(
        URL(filePath: "/Users/example/work/app/.git/logo.png")
      ) == .project
    )
  }

  @Test("filters by date color keyword OCR and source")
  func filtersByRichMetadata() {
    let date = Date(timeIntervalSince1970: 2_000)
    let asset = makeAsset(
      filename: "card.png",
      url: URL(filePath: "/Users/example/Downloads/card.png"),
      createdAt: date,
      modifiedAt: date
    )
    let enrichment = makeEnrichment(
      assetID: asset.id,
      ocrText: "Invoice ABC",
      keywords: ["finance"],
      dominantColors: ["#2040A0"]
    )
    let query = AssetQuery(
      searchText: "invoice #2040a0",
      createdAfter: Date(timeIntervalSince1970: 1_000),
      modifiedBefore: Date(timeIntervalSince1970: 3_000),
      colors: ["#2040a0"],
      keywords: ["finance"],
      sources: [.downloads]
    )

    let result = query.apply(to: [asset], enrichments: [asset.id: enrichment])

    #expect(result == [asset])
  }

  @Test("sorts assets by metadata")
  func sortsAssetsByMetadata() {
    let small = makeAsset(
      filename: "b.png",
      url: URL(filePath: "/tmp/b.png"),
      fileSize: 10,
      modifiedAt: Date(timeIntervalSince1970: 200)
    )
    let large = makeAsset(
      filename: "a.png",
      url: URL(filePath: "/tmp/a.png"),
      fileSize: 20,
      modifiedAt: Date(timeIntervalSince1970: 100)
    )

    #expect(
      AssetQuery(sort: .fileSize(order: .descending))
        .apply(to: [small, large], enrichments: [:]) == [large, small]
    )
    #expect(
      AssetQuery(sort: .filename(order: .ascending))
        .apply(to: [small, large], enrichments: [:]) == [large, small]
    )
  }

  @Test("builds smart views from indexed metadata")
  func buildsSmartViews() {
    let now = Date(timeIntervalSince1970: 2_000)
    let screenshot = makeAsset(
      filename: "Screenshot 2026-06-21 at 11.00.png",
      url: URL(filePath: "/tmp/Desktop/Screenshot 2026.png")
    )
    let download = makeAsset(
      filename: "download.png",
      url: URL(filePath: "/Users/example/Downloads/download.png"),
      createdAt: now.addingTimeInterval(-60)
    )
    let large = makeAsset(
      filename: "large.tiff",
      url: URL(filePath: "/tmp/large.tiff"),
      fileSize: 60_000_000
    )

    #expect(
      SmartAssetView.screenshots.assets(in: [screenshot, download, large], now: now) == [screenshot]
    )
    #expect(
      SmartAssetView.recentDownloads.assets(in: [screenshot, download, large], now: now) == [
        download
      ])
    #expect(
      SmartAssetView.largeFiles.assets(in: [screenshot, download, large], now: now) == [large])
  }
}

private func makeAsset(
  id: AssetID = AssetID(volumeIdentifier: UUID().uuidString, fileIdentifier: UUID().uuidString),
  filename: String,
  url: URL,
  contentType: String = "public.png",
  fileSize: Int64 = 1_000,
  createdAt: Date? = nil,
  modifiedAt: Date? = nil,
  pixelWidth: Int? = 100,
  pixelHeight: Int? = 100
) -> ImageAsset {
  ImageAsset(
    id: id,
    url: url,
    filename: filename,
    contentType: contentType,
    fileSize: fileSize,
    createdAt: createdAt,
    modifiedAt: modifiedAt,
    pixelWidth: pixelWidth,
    pixelHeight: pixelHeight
  )
}

private func makeEnrichment(
  assetID: AssetID,
  ocrText: String = "launch hero image",
  keywords: [String] = ["marketing"],
  dominantColors: [String] = []
) -> AssetEnrichment {
  AssetEnrichment(
    assetID: assetID,
    exactHash: "hash",
    perceptualHash: 0,
    thumbnailURL: URL(filePath: "/tmp/thumb.jpg"),
    exif: AssetEXIF(
      cameraMake: nil,
      cameraModel: nil,
      lensModel: nil,
      capturedAt: nil,
      orientation: nil,
      isoSpeed: nil,
      focalLength: nil,
      aperture: nil,
      exposureTime: nil,
      ocrText: ocrText,
      keywords: keywords,
      dominantColors: dominantColors
    ),
    indexedAt: Date(timeIntervalSince1970: 1_000)
  )
}
