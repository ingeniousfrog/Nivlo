import Foundation
import UniformTypeIdentifiers

public enum AssetMediaKind: Equatable, Sendable {
  case image
  case video
  case unsupported
}

extension ImageAsset {
  public var mediaKind: AssetMediaKind {
    guard let type = UTType(contentType) else {
      return .unsupported
    }
    if type.conforms(to: .image) {
      return .image
    }
    if type.conforms(to: .movie) {
      return .video
    }
    return .unsupported
  }
}

public struct VideoTrimRange: Equatable, Sendable {
  public let startSeconds: Double
  public let endSeconds: Double

  public init(
    startSeconds: Double,
    endSeconds: Double,
    durationSeconds: Double,
    minimumDurationSeconds: Double = 0.1
  ) {
    let duration = max(0, durationSeconds)
    let minimumDuration = min(max(0.01, minimumDurationSeconds), max(0.01, duration))
    let requestedStart = min(max(0, startSeconds), duration)
    let requestedEnd = min(max(0, endSeconds), duration)

    if requestedEnd - requestedStart >= minimumDuration {
      self.startSeconds = requestedStart
      self.endSeconds = requestedEnd
    } else {
      self.endSeconds = duration
      self.startSeconds = max(0, duration - minimumDuration)
    }
  }
}
