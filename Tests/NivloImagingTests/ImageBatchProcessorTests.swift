import Foundation
import ImageIO
import NivloDomain
import Testing
import UniformTypeIdentifiers

@testable import NivloImaging

@Suite("Image batch processor")
struct ImageBatchProcessorTests {
  @Test("resizes and converts images into an output directory without changing the source")
  func resizesAndConvertsWithoutChangingSource() async throws {
    let fixture = try BatchProcessingFixture(width: 100, height: 60)
    let originalData = try Data(contentsOf: fixture.imageURL)
    let processor = ImageBatchProcessor()

    let outputs = try await processor.process(
      ImageBatchRequest(
        assets: [fixture.asset],
        outputDirectory: fixture.outputURL,
        format: .jpeg,
        compressionQuality: 0.7,
        maxPixelSize: 40,
        filenameTemplate: "export-{index}"
      )
    )
    let dimensions = try imageDimensions(at: outputs[0].url)

    #expect(outputs.count == 1)
    #expect(outputs[0].url.lastPathComponent == "export-1.jpg")
    #expect(max(dimensions.width, dimensions.height) <= 40)
    #expect(try Data(contentsOf: fixture.imageURL) == originalData)
  }

  @Test("adds a suffix instead of overwriting existing output")
  func avoidsOverwritingExistingOutput() async throws {
    let fixture = try BatchProcessingFixture(width: 20, height: 20)
    try FileManager.default.createDirectory(
      at: fixture.outputURL,
      withIntermediateDirectories: true
    )
    try Data("existing".utf8).write(to: fixture.outputURL.appending(path: "asset.png"))
    let processor = ImageBatchProcessor()

    let outputs = try await processor.process(
      ImageBatchRequest(
        assets: [fixture.asset],
        outputDirectory: fixture.outputURL,
        format: .png,
        filenameTemplate: "asset"
      )
    )

    #expect(outputs[0].url.lastPathComponent == "asset-1.png")
    #expect(
      try Data(contentsOf: fixture.outputURL.appending(path: "asset.png")) == Data("existing".utf8))
  }
}

private struct BatchProcessingFixture {
  let rootURL: URL
  let imageURL: URL
  let outputURL: URL
  let asset: ImageAsset

  init(width: Int, height: Int) throws {
    rootURL = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    imageURL = rootURL.appending(path: "source.png")
    outputURL = rootURL.appending(path: "exports", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: rootURL,
      withIntermediateDirectories: true
    )
    try writeFixtureImage(at: imageURL, width: width, height: height)
    asset = ImageAsset(
      id: AssetID(volumeIdentifier: "volume", fileIdentifier: "asset"),
      url: imageURL,
      filename: imageURL.lastPathComponent,
      contentType: UTType.png.identifier,
      fileSize: Int64(try Data(contentsOf: imageURL).count),
      createdAt: nil,
      modifiedAt: nil,
      pixelWidth: width,
      pixelHeight: height
    )
  }
}

private func writeFixtureImage(
  at url: URL,
  width: Int,
  height: Int
) throws {
  guard
    let context = CGContext(
      data: nil,
      width: width,
      height: height,
      bitsPerComponent: 8,
      bytesPerRow: width * 4,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )
  else {
    throw BatchProcessingFixtureError.creationFailed
  }
  context.setFillColor(CGColor(red: 0.8, green: 0.2, blue: 0.1, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: width, height: height))
  guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else {
    throw BatchProcessingFixtureError.creationFailed
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw BatchProcessingFixtureError.creationFailed
  }
}

private func imageDimensions(at url: URL) throws -> (width: Int, height: Int) {
  guard
    let source = CGImageSourceCreateWithURL(url as CFURL, nil),
    let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
      as? [CFString: Any],
    let width = properties[kCGImagePropertyPixelWidth] as? Int,
    let height = properties[kCGImagePropertyPixelHeight] as? Int
  else {
    throw BatchProcessingFixtureError.creationFailed
  }
  return (width, height)
}

private enum BatchProcessingFixtureError: Error {
  case creationFailed
}
