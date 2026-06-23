import CoreGraphics
import Foundation
import ImageIO
import NivloImaging
import Testing
import UniformTypeIdentifiers

@Suite("Image histogram analyzer")
struct ImageHistogramAnalyzerTests {
  @Test("computes RGB luminance bins and clipping counts")
  func histogram() throws {
    let url = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString).png")
    try writeSplitHistogramFixture(to: url)

    let histogram = try ImageHistogramAnalyzer().analyze(url: url)

    #expect(histogram.red.bins[255] > 0)
    #expect(histogram.green.bins[0] > 0)
    #expect(histogram.luminance.totalCount == 200)
    #expect(histogram.shadowClippingCount > 0)
    #expect(histogram.highlightClippingCount > 0)
  }
}

private func writeSplitHistogramFixture(to url: URL) throws {
  let width = 20
  let height = 10
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
    throw HistogramFixtureError.creationFailed
  }
  context.setFillColor(CGColor(gray: 0, alpha: 1))
  context.fill(CGRect(x: 0, y: 0, width: 10, height: 10))
  context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
  context.fill(CGRect(x: 10, y: 0, width: 10, height: 10))
  guard
    let image = context.makeImage(),
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType.png.identifier as CFString,
      1,
      nil
    )
  else {
    throw HistogramFixtureError.creationFailed
  }
  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw HistogramFixtureError.creationFailed
  }
}

private enum HistogramFixtureError: Error {
  case creationFailed
}
