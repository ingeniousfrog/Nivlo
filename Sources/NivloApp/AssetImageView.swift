import AVFoundation
import AppKit
import ImageIO
import NivloDomain
import SwiftUI

struct AssetImageView: View {
  let asset: ImageAsset
  let enrichment: AssetEnrichment?
  let maxPixelSize: Int
  let contentMode: ContentMode

  init(
    asset: ImageAsset,
    enrichment: AssetEnrichment?,
    maxPixelSize: Int,
    contentMode: ContentMode = .fill
  ) {
    self.asset = asset
    self.enrichment = enrichment
    self.maxPixelSize = maxPixelSize
    self.contentMode = contentMode
  }

  @State private var image: NSImage?
  @State private var isLoading = false

  var body: some View {
    ZStack {
      if let image {
        Image(nsImage: image)
          .resizable()
          .aspectRatio(contentMode: contentMode)
      } else {
        placeholder
      }
      if isLoading && image == nil {
        ProgressView()
          .controlSize(.small)
      }
    }
    .task(id: loadKey) {
      await loadImage()
    }
  }

  private var placeholder: some View {
    ZStack {
      Color.secondary.opacity(0.12)
      Image(systemName: "photo")
        .font(.largeTitle)
        .foregroundStyle(.secondary)
    }
  }

  private var loadKey: String {
    [
      enrichment?.thumbnailURL.standardizedFileURL.path ?? "",
      asset.url.standardizedFileURL.path,
      "\(maxPixelSize)",
    ].joined(separator: "|")
  }

  private func loadImage() async {
    image = nil
    isLoading = true
    let thumbnailURL = enrichment?.thumbnailURL
    let sourceURL = asset.url
    let maxPixelSize = maxPixelSize
    let data = await Task.detached(priority: .userInitiated) {
      AssetImageDataLoader.imageData(
        sourceURL: sourceURL,
        thumbnailURL: thumbnailURL,
        maxPixelSize: maxPixelSize
      )
    }.value
    guard !Task.isCancelled else {
      return
    }
    image = data.flatMap(NSImage.init(data:))
    isLoading = false
  }
}

private enum AssetImageDataLoader {
  static func imageData(
    sourceURL: URL,
    thumbnailURL: URL?,
    maxPixelSize: Int
  ) -> Data? {
    if let thumbnailURL,
      let cachedData = try? Data(contentsOf: thumbnailURL)
    {
      return cachedData
    }

    if let imageData = rasterImageData(sourceURL: sourceURL, maxPixelSize: maxPixelSize) {
      return imageData
    }

    return videoPosterData(sourceURL: sourceURL, maxPixelSize: maxPixelSize)
  }

  private static func rasterImageData(
    sourceURL: URL,
    maxPixelSize: Int
  ) -> Data? {
    guard
      let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let thumbnail = CGImageSourceCreateThumbnailAtIndex(
        source,
        0,
        [
          kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: max(1, maxPixelSize),
          kCGImageSourceCreateThumbnailWithTransform: true,
        ] as CFDictionary
      )
    else {
      return nil
    }

    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        "public.jpeg" as CFString,
        1,
        nil
      )
    else {
      return nil
    }
    CGImageDestinationAddImage(destination, thumbnail, nil)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return data as Data
  }

  private static func videoPosterData(
    sourceURL: URL,
    maxPixelSize: Int
  ) -> Data? {
    let asset = AVURLAsset(url: sourceURL)
    let generator = AVAssetImageGenerator(asset: asset)
    generator.appliesPreferredTrackTransform = true
    generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
    guard
      let frame = try? generator.copyCGImage(
        at: .zero,
        actualTime: nil
      )
    else {
      return nil
    }

    let data = NSMutableData()
    guard
      let destination = CGImageDestinationCreateWithData(
        data,
        "public.jpeg" as CFString,
        1,
        nil
      )
    else {
      return nil
    }
    CGImageDestinationAddImage(destination, frame, nil)
    guard CGImageDestinationFinalize(destination) else {
      return nil
    }
    return data as Data
  }
}
