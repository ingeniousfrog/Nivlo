import AVFoundation
import Foundation
import NivloDomain

public struct VideoMetadataLoader: Sendable {
  private let ffprobe: FFprobeService

  public init(ffprobe: FFprobeService = FFprobeService()) {
    self.ffprobe = ffprobe
  }

  public func load(url: URL) async -> VideoProbeInfo? {
    if let probe = try? await ffprobe.probe(sourceURL: url) {
      return probe
    }
    return await avFoundationProbe(url: url)
  }

  private func avFoundationProbe(url: URL) async -> VideoProbeInfo? {
    let asset = AVURLAsset(url: url)
    guard
      let duration = try? await asset.load(.duration).seconds,
      duration.isFinite,
      duration > 0
    else {
      return nil
    }

    let tracks = (try? await asset.load(.tracks)) ?? []
    let videoTrack = tracks.first { $0.mediaType == .video }
    let audioTracks = tracks.filter { $0.mediaType == .audio }
    let naturalSize = try? await videoTrack?.load(.naturalSize)
    let preferredTransform = try? await videoTrack?.load(.preferredTransform)
    let frameRate = try? await videoTrack?.load(.nominalFrameRate)

    let transformedSize = naturalSize.map {
      $0.applying(preferredTransform ?? .identity)
    }
    let width = Int(abs(transformedSize?.width ?? 0).rounded())
    let height = Int(abs(transformedSize?.height ?? 0).rounded())

    return VideoProbeInfo(
      durationSeconds: duration,
      width: width,
      height: height,
      frameRate: Double(frameRate ?? 0),
      hasAudio: !audioTracks.isEmpty
    )
  }
}
