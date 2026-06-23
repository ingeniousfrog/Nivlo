import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

public struct VideoTimelineThumbnail: Equatable, Sendable {
  public let timeSeconds: Double
  public let imageData: Data

  public init(timeSeconds: Double, imageData: Data) {
    self.timeSeconds = timeSeconds
    self.imageData = imageData
  }
}

public enum VideoTimelineAnalyzerError: Error, LocalizedError, Sendable {
  case invalidDuration
  case frameExtractionFailed
  case imageEncodingFailed
  case audioUnavailable

  public var errorDescription: String? {
    switch self {
    case .invalidDuration:
      "The media duration is unavailable."
    case .frameExtractionFailed:
      "A timeline frame could not be extracted."
    case .imageEncodingFailed:
      "A timeline thumbnail could not be encoded."
    case .audioUnavailable:
      "The media does not contain a readable audio track."
    }
  }
}

public struct VideoTimelineAnalyzer: Sendable {
  public init() {}

  public func thumbnails(
    sourceURL: URL,
    count: Int = 12,
    maximumSize: CGSize = CGSize(width: 240, height: 135)
  ) async throws -> [VideoTimelineThumbnail] {
    let requestedCount = max(1, count)
    return try await Task.detached(priority: .utility) {
      let asset = AVURLAsset(url: sourceURL)
      let duration = try await asset.load(.duration).seconds
      guard duration.isFinite, duration > 0 else {
        throw VideoTimelineAnalyzerError.invalidDuration
      }
      let generator = AVAssetImageGenerator(asset: asset)
      generator.appliesPreferredTrackTransform = true
      generator.maximumSize = maximumSize
      generator.requestedTimeToleranceBefore = .zero
      generator.requestedTimeToleranceAfter = .zero

      return try (0..<requestedCount).map { index in
        let fraction =
          requestedCount == 1
          ? 0.5
          : Double(index) / Double(requestedCount - 1)
        let seconds = min(
          max(0, duration * fraction),
          max(0, duration - 0.001)
        )
        var actualTime = CMTime.zero
        let image: CGImage
        do {
          image = try generator.copyCGImage(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            actualTime: &actualTime
          )
        } catch {
          throw VideoTimelineAnalyzerError.frameExtractionFailed
        }
        return VideoTimelineThumbnail(
          timeSeconds: actualTime.seconds.isFinite
            ? actualTime.seconds : seconds,
          imageData: try encodeJPEG(image)
        )
      }
    }.value
  }

  public func waveform(
    sourceURL: URL,
    sampleCount: Int = 256
  ) throws -> [Double] {
    let sampleCount = max(1, sampleCount)
    let audioFile: AVAudioFile
    do {
      audioFile = try AVAudioFile(forReading: sourceURL)
    } catch {
      throw VideoTimelineAnalyzerError.audioUnavailable
    }
    let totalFrames = max(1, Int(audioFile.length))
    let capacity = AVAudioFrameCount(min(8_192, totalFrames))
    guard
      let buffer = AVAudioPCMBuffer(
        pcmFormat: audioFile.processingFormat,
        frameCapacity: capacity
      )
    else {
      throw VideoTimelineAnalyzerError.audioUnavailable
    }
    var result = [Double](repeating: 0, count: sampleCount)
    var frameOffset = 0
    while frameOffset < totalFrames {
      let remaining = min(Int(capacity), totalFrames - frameOffset)
      try audioFile.read(
        into: buffer,
        frameCount: AVAudioFrameCount(remaining)
      )
      guard let channels = buffer.floatChannelData else {
        throw VideoTimelineAnalyzerError.audioUnavailable
      }
      let channelCount = Int(buffer.format.channelCount)
      let frameLength = Int(buffer.frameLength)
      for frame in 0..<frameLength {
        var peak = 0.0
        for channel in 0..<channelCount {
          peak = max(peak, abs(Double(channels[channel][frame])))
        }
        let index = min(
          sampleCount - 1,
          (frameOffset + frame) * sampleCount / totalFrames
        )
        result[index] = max(result[index], min(1, peak))
      }
      frameOffset += frameLength
      guard frameLength > 0 else { break }
    }
    return result
  }

  public func waveformAsync(
    sourceURL: URL,
    sampleCount: Int = 256
  ) async throws -> [Double] {
    try await Task.detached(priority: .utility) {
      try waveform(sourceURL: sourceURL, sampleCount: sampleCount)
    }.value
  }
}

private func encodeJPEG(_ image: CGImage) throws -> Data {
  let data = NSMutableData()
  guard
    let destination = CGImageDestinationCreateWithData(
      data,
      UTType.jpeg.identifier as CFString,
      1,
      nil
    )
  else {
    throw VideoTimelineAnalyzerError.imageEncodingFailed
  }
  CGImageDestinationAddImage(
    destination,
    image,
    [kCGImageDestinationLossyCompressionQuality: 0.72] as CFDictionary
  )
  guard CGImageDestinationFinalize(destination) else {
    throw VideoTimelineAnalyzerError.imageEncodingFailed
  }
  return data as Data
}
