import AVFoundation
import CoreVideo
import Foundation
import NivloImaging
import Testing

@Suite("Video timeline analyzer")
struct VideoTimelineAnalyzerTests {
  @Test("extracts frame accurate timeline thumbnails from a real video")
  func thumbnails() async throws {
    let videoURL = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString).mov")
    try writeVideoFixture(to: videoURL)

    let thumbnails = try await VideoTimelineAnalyzer().thumbnails(
      sourceURL: videoURL,
      count: 4
    )

    #expect(thumbnails.count == 4)
    #expect(thumbnails.allSatisfy { !$0.imageData.isEmpty })
    #expect(thumbnails.map(\.timeSeconds) == thumbnails.map(\.timeSeconds).sorted())
  }

  @Test("extracts a bounded waveform from a real audio file")
  func waveform() throws {
    let audioURL = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString).caf")
    try writeAudioFixture(to: audioURL)

    let waveform = try VideoTimelineAnalyzer().waveform(
      sourceURL: audioURL,
      sampleCount: 64
    )

    #expect(waveform.count == 64)
    #expect(waveform.contains { $0 > 0.2 })
    #expect(waveform.allSatisfy { $0 >= 0 && $0 <= 1 })
  }
}

private func writeVideoFixture(to url: URL) throws {
  let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
  let input = AVAssetWriterInput(
    mediaType: .video,
    outputSettings: [
      AVVideoCodecKey: AVVideoCodecType.h264,
      AVVideoWidthKey: 64,
      AVVideoHeightKey: 64,
    ]
  )
  let adaptor = AVAssetWriterInputPixelBufferAdaptor(
    assetWriterInput: input,
    sourcePixelBufferAttributes: [
      kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_32BGRA,
      kCVPixelBufferWidthKey as String: 64,
      kCVPixelBufferHeightKey as String: 64,
    ]
  )
  guard writer.canAdd(input) else {
    throw VideoFixtureError.creationFailed
  }
  writer.add(input)
  guard writer.startWriting() else {
    throw writer.error ?? VideoFixtureError.creationFailed
  }
  writer.startSession(atSourceTime: .zero)
  for frame in 0..<8 {
    while !input.isReadyForMoreMediaData {
      Thread.sleep(forTimeInterval: 0.001)
    }
    guard let pool = adaptor.pixelBufferPool else {
      throw VideoFixtureError.creationFailed
    }
    var buffer: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
    guard let buffer else {
      throw VideoFixtureError.creationFailed
    }
    CVPixelBufferLockBaseAddress(buffer, [])
    memset(
      CVPixelBufferGetBaseAddress(buffer),
      Int32(frame * 24),
      CVPixelBufferGetDataSize(buffer)
    )
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(
      buffer,
      withPresentationTime: CMTime(value: Int64(frame), timescale: 4)
    )
  }
  input.markAsFinished()
  let semaphore = DispatchSemaphore(value: 0)
  writer.finishWriting {
    semaphore.signal()
  }
  semaphore.wait()
  guard writer.status == .completed else {
    throw writer.error ?? VideoFixtureError.creationFailed
  }
}

private func writeAudioFixture(to url: URL) throws {
  let format = AVAudioFormat(
    standardFormatWithSampleRate: 8_000,
    channels: 1
  )!
  let file = try AVAudioFile(
    forWriting: url,
    settings: format.settings
  )
  let frameCount: AVAudioFrameCount = 8_000
  let buffer = AVAudioPCMBuffer(
    pcmFormat: format,
    frameCapacity: frameCount
  )!
  buffer.frameLength = frameCount
  let channel = buffer.floatChannelData![0]
  for index in 0..<Int(frameCount) {
    channel[index] = Float(sin(Double(index) / 20) * 0.7)
  }
  try file.write(from: buffer)
}

private enum VideoFixtureError: Error {
  case creationFailed
}
