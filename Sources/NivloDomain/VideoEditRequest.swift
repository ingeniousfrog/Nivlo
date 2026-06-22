import Foundation

public enum VideoOutputFormat: String, Sendable, Codable, CaseIterable {
  case mp4
  case webm
  case mov
}

public enum VideoAudioExportFormat: String, Sendable, Codable, CaseIterable {
  case m4a
  case mp3
}

public struct VideoCropRect: Equatable, Sendable, Codable {
  public var x: Int
  public var y: Int
  public var width: Int
  public var height: Int

  public init(x: Int, y: Int, width: Int, height: Int) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
  }
}

public struct VideoEditRequest: Sendable, Equatable {
  public let sourceURL: URL
  public let outputURL: URL
  public var trimRange: VideoTrimRange
  public var cropRect: VideoCropRect?
  public var scaleWidth: Int?
  public var scaleHeight: Int?
  public var transposeQuarterTurns: Int
  public var outputFPS: Double?
  public var videoCodec: String
  public var crf: Int
  public var preset: String
  public var outputFormat: VideoOutputFormat
  public var extractAudioOnly: Bool
  public var audioFormat: VideoAudioExportFormat

  public init(
    sourceURL: URL,
    outputURL: URL,
    trimRange: VideoTrimRange,
    cropRect: VideoCropRect? = nil,
    scaleWidth: Int? = nil,
    scaleHeight: Int? = nil,
    transposeQuarterTurns: Int = 0,
    outputFPS: Double? = nil,
    videoCodec: String = "libx264",
    crf: Int = 23,
    preset: String = "medium",
    outputFormat: VideoOutputFormat = .mp4,
    extractAudioOnly: Bool = false,
    audioFormat: VideoAudioExportFormat = .m4a
  ) {
    self.sourceURL = sourceURL
    self.outputURL = outputURL
    self.trimRange = trimRange
    self.cropRect = cropRect
    self.scaleWidth = scaleWidth
    self.scaleHeight = scaleHeight
    self.transposeQuarterTurns = transposeQuarterTurns
    self.outputFPS = outputFPS
    self.videoCodec = videoCodec
    self.crf = crf
    self.preset = preset
    self.outputFormat = outputFormat
    self.extractAudioOnly = extractAudioOnly
    self.audioFormat = audioFormat
  }
}

public struct VideoProbeInfo: Sendable, Equatable {
  public let durationSeconds: Double
  public let width: Int
  public let height: Int
  public let frameRate: Double
  public let hasAudio: Bool

  public init(
    durationSeconds: Double,
    width: Int,
    height: Int,
    frameRate: Double,
    hasAudio: Bool
  ) {
    self.durationSeconds = durationSeconds
    self.width = width
    self.height = height
    self.frameRate = frameRate
    self.hasAudio = hasAudio
  }
}

public struct FFmpegExportProgress: Sendable, Equatable {
  public let processedSeconds: Double
  public let totalSeconds: Double?

  public init(processedSeconds: Double, totalSeconds: Double?) {
    self.processedSeconds = processedSeconds
    self.totalSeconds = totalSeconds
  }

  public var fraction: Double? {
    guard let totalSeconds, totalSeconds > 0 else {
      return nil
    }
    return min(1, max(0, processedSeconds / totalSeconds))
  }
}
