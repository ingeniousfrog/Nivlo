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

  public init(
    normalized: NormalizedCropRect,
    sourceWidth: Int,
    sourceHeight: Int
  ) {
    let crop = normalized.clamped()
    let maximumWidth = max(2, sourceWidth)
    let maximumHeight = max(2, sourceHeight)
    let x = Self.evenFloor(crop.x * Double(maximumWidth))
    let y = Self.evenFloor(crop.y * Double(maximumHeight))
    let width = min(
      Self.evenFloor(crop.width * Double(maximumWidth)),
      Self.evenFloor(Double(maximumWidth - x))
    )
    let height = min(
      Self.evenFloor(crop.height * Double(maximumHeight)),
      Self.evenFloor(Double(maximumHeight - y))
    )
    self.init(
      x: max(0, x),
      y: max(0, y),
      width: max(2, width),
      height: max(2, height)
    )
  }

  private static func evenFloor(_ value: Double) -> Int {
    max(0, Int(value.rounded(.down)) / 2 * 2)
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
  public var volume: Double
  public var fadeInSeconds: Double
  public var fadeOutSeconds: Double

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
    audioFormat: VideoAudioExportFormat = .m4a,
    volume: Double = 1,
    fadeInSeconds: Double = 0,
    fadeOutSeconds: Double = 0
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
    self.volume = min(max(volume, 0), 2)
    self.fadeInSeconds = max(0, fadeInSeconds)
    self.fadeOutSeconds = max(0, fadeOutSeconds)
  }
}

public struct VideoEditSession: Codable, Equatable, Sendable {
  public var sourceURL: URL
  public var durationSeconds: Double
  public var startSeconds: Double
  public var endSeconds: Double
  public var normalizedCrop: NormalizedCropRect
  public var scaleWidth: Int?
  public var scaleHeight: Int?
  public var transposeQuarterTurns: Int
  public var outputFPS: Double?
  public var volume: Double
  public var fadeInSeconds: Double
  public var fadeOutSeconds: Double
  public var exportPresetID: String
  public var outputFormat: VideoOutputFormat
  public var extractAudioOnly: Bool
  public var audioFormat: VideoAudioExportFormat

  public init(
    sourceURL: URL,
    durationSeconds: Double,
    startSeconds: Double = 0,
    endSeconds: Double? = nil,
    normalizedCrop: NormalizedCropRect = .full,
    scaleWidth: Int? = nil,
    scaleHeight: Int? = nil,
    transposeQuarterTurns: Int = 0,
    outputFPS: Double? = nil,
    volume: Double = 1,
    fadeInSeconds: Double = 0,
    fadeOutSeconds: Double = 0,
    exportPresetID: String = "h264-balanced",
    outputFormat: VideoOutputFormat = .mp4,
    extractAudioOnly: Bool = false,
    audioFormat: VideoAudioExportFormat = .m4a
  ) {
    self.sourceURL = sourceURL
    self.durationSeconds = max(0, durationSeconds)
    self.startSeconds = min(max(0, startSeconds), self.durationSeconds)
    self.endSeconds = min(
      max(endSeconds ?? self.durationSeconds, self.startSeconds),
      self.durationSeconds
    )
    self.normalizedCrop = normalizedCrop.clamped()
    self.scaleWidth = scaleWidth
    self.scaleHeight = scaleHeight
    self.transposeQuarterTurns = (transposeQuarterTurns % 4 + 4) % 4
    self.outputFPS = outputFPS
    self.volume = min(max(volume, 0), 2)
    self.fadeInSeconds = max(0, fadeInSeconds)
    self.fadeOutSeconds = max(0, fadeOutSeconds)
    self.exportPresetID = exportPresetID
    self.outputFormat = outputFormat
    self.extractAudioOnly = extractAudioOnly
    self.audioFormat = audioFormat
  }

  private enum CodingKeys: String, CodingKey {
    case sourceURL
    case durationSeconds
    case startSeconds
    case endSeconds
    case normalizedCrop
    case scaleWidth
    case scaleHeight
    case transposeQuarterTurns
    case outputFPS
    case volume
    case fadeInSeconds
    case fadeOutSeconds
    case exportPresetID
    case outputFormat
    case extractAudioOnly
    case audioFormat
  }

  public init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    self.init(
      sourceURL: try container.decode(URL.self, forKey: .sourceURL),
      durationSeconds: try container.decode(Double.self, forKey: .durationSeconds),
      startSeconds: try container.decodeIfPresent(Double.self, forKey: .startSeconds) ?? 0,
      endSeconds: try container.decodeIfPresent(Double.self, forKey: .endSeconds),
      normalizedCrop:
        try container.decodeIfPresent(NormalizedCropRect.self, forKey: .normalizedCrop) ?? .full,
      scaleWidth: try container.decodeIfPresent(Int.self, forKey: .scaleWidth),
      scaleHeight: try container.decodeIfPresent(Int.self, forKey: .scaleHeight),
      transposeQuarterTurns:
        try container.decodeIfPresent(Int.self, forKey: .transposeQuarterTurns) ?? 0,
      outputFPS: try container.decodeIfPresent(Double.self, forKey: .outputFPS),
      volume: try container.decodeIfPresent(Double.self, forKey: .volume) ?? 1,
      fadeInSeconds: try container.decodeIfPresent(Double.self, forKey: .fadeInSeconds) ?? 0,
      fadeOutSeconds: try container.decodeIfPresent(Double.self, forKey: .fadeOutSeconds) ?? 0,
      exportPresetID:
        try container.decodeIfPresent(String.self, forKey: .exportPresetID) ?? "h264-balanced",
      outputFormat:
        try container.decodeIfPresent(VideoOutputFormat.self, forKey: .outputFormat) ?? .mp4,
      extractAudioOnly:
        try container.decodeIfPresent(Bool.self, forKey: .extractAudioOnly) ?? false,
      audioFormat:
        try container.decodeIfPresent(VideoAudioExportFormat.self, forKey: .audioFormat) ?? .m4a
    )
  }
}

public struct VideoExportPreset: Identifiable, Codable, Equatable, Sendable {
  public let id: String
  public var name: String
  public var outputFormat: VideoOutputFormat
  public var softwareCodec: String
  public var hardwareCodec: String?
  public var crf: Int
  public var encoderPreset: String

  public init(
    id: String,
    name: String,
    outputFormat: VideoOutputFormat,
    softwareCodec: String,
    hardwareCodec: String? = nil,
    crf: Int,
    encoderPreset: String
  ) {
    self.id = id
    self.name = name
    self.outputFormat = outputFormat
    self.softwareCodec = softwareCodec
    self.hardwareCodec = hardwareCodec
    self.crf = crf
    self.encoderPreset = encoderPreset
  }

  public static let builtIn: [VideoExportPreset] = [
    VideoExportPreset(
      id: "h264-balanced",
      name: "H.264 Balanced",
      outputFormat: .mp4,
      softwareCodec: "libx264",
      hardwareCodec: "h264_videotoolbox",
      crf: 23,
      encoderPreset: "medium"
    ),
    VideoExportPreset(
      id: "hevc-quality",
      name: "HEVC Quality",
      outputFormat: .mov,
      softwareCodec: "libx265",
      hardwareCodec: "hevc_videotoolbox",
      crf: 21,
      encoderPreset: "slow"
    ),
    VideoExportPreset(
      id: "webm",
      name: "WebM",
      outputFormat: .webm,
      softwareCodec: "libvpx-vp9",
      crf: 30,
      encoderPreset: "medium"
    ),
  ]
}

public struct VideoProbeInfo: Sendable, Equatable {
  public let durationSeconds: Double
  public let width: Int
  public let height: Int
  public let frameRate: Double
  public let hasAudio: Bool
  public let videoCodec: String?
  public let audioCodec: String?

  public init(
    durationSeconds: Double,
    width: Int,
    height: Int,
    frameRate: Double,
    hasAudio: Bool,
    videoCodec: String? = nil,
    audioCodec: String? = nil
  ) {
    self.durationSeconds = durationSeconds
    self.width = width
    self.height = height
    self.frameRate = frameRate
    self.hasAudio = hasAudio
    self.videoCodec = videoCodec?.nilIfBlank
    self.audioCodec = audioCodec?.nilIfBlank
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

private extension String {
  var nilIfBlank: String? {
    let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }
}
