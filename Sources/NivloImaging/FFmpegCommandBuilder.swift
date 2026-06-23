import Foundation
import NivloDomain

public struct FFmpegCommandBuilder: Sendable, Equatable {
  public let executable: URL
  public let arguments: [String]

  public init(executable: URL, arguments: [String]) {
    self.executable = executable
    self.arguments = arguments
  }

  public static func build(request: VideoEditRequest, ffmpegExecutable: URL) -> FFmpegCommandBuilder
  {
    if request.extractAudioOnly {
      return buildAudioExtract(request: request, ffmpegExecutable: ffmpegExecutable)
    }

    var filters: [String] = []
    if let crop = request.cropRect {
      filters.append("crop=\(crop.width):\(crop.height):\(crop.x):\(crop.y)")
    }
    if let scaleWidth = request.scaleWidth, let scaleHeight = request.scaleHeight {
      filters.append("scale=\(scaleWidth):\(scaleHeight)")
    }
    if request.transposeQuarterTurns > 0 {
      let turns = ((request.transposeQuarterTurns % 4) + 4) % 4
      if turns == 1 {
        filters.append("transpose=1")
      } else if turns == 2 {
        filters.append("transpose=1,transpose=1")
      } else if turns == 3 {
        filters.append("transpose=2")
      }
    }
    if let fps = request.outputFPS {
      filters.append("fps=\(fps)")
    }

    var arguments = [
      "-y",
      "-ss",
      formatSeconds(request.trimRange.startSeconds),
      "-to",
      formatSeconds(request.trimRange.endSeconds),
      "-i",
      request.sourceURL.path,
    ]
    if !filters.isEmpty {
      arguments.append(contentsOf: ["-vf", filters.joined(separator: ",")])
    }
    let audioFilters = buildAudioFilters(request)
    if !audioFilters.isEmpty {
      arguments.append(contentsOf: ["-af", audioFilters.joined(separator: ",")])
    }
    arguments.append(contentsOf: ["-c:v", request.videoCodec])
    if request.videoCodec.hasSuffix("_videotoolbox") {
      arguments.append(contentsOf: [
        "-q:v",
        String(max(1, min(100, 100 - request.crf * 2))),
      ])
    } else {
      arguments.append(contentsOf: [
        "-crf",
        String(request.crf),
        "-preset",
        request.preset,
      ])
    }
    arguments.append(contentsOf: [
      "-c:a",
      "aac",
      request.outputURL.path,
    ])
    return FFmpegCommandBuilder(executable: ffmpegExecutable, arguments: arguments)
  }

  public static func buildAudioExtract(
    request: VideoEditRequest,
    ffmpegExecutable: URL
  ) -> FFmpegCommandBuilder {
    var arguments = [
      "-y",
      "-ss",
      formatSeconds(request.trimRange.startSeconds),
      "-to",
      formatSeconds(request.trimRange.endSeconds),
      "-i",
      request.sourceURL.path,
      "-vn",
    ]
    switch request.audioFormat {
    case .m4a:
      arguments.append(contentsOf: ["-c:a", "aac", request.outputURL.path])
    case .mp3:
      arguments.append(contentsOf: ["-c:a", "libmp3lame", "-q:a", "2", request.outputURL.path])
    }
    let audioFilters = buildAudioFilters(request)
    if !audioFilters.isEmpty {
      let outputURL = arguments.removeLast()
      arguments.append(contentsOf: ["-af", audioFilters.joined(separator: ","), outputURL])
    }
    return FFmpegCommandBuilder(executable: ffmpegExecutable, arguments: arguments)
  }

  private static func buildAudioFilters(_ request: VideoEditRequest) -> [String] {
    var filters: [String] = []
    if request.volume != 1 {
      filters.append("volume=\(request.volume)")
    }
    let duration = max(
      0,
      request.trimRange.endSeconds - request.trimRange.startSeconds
    )
    if request.fadeInSeconds > 0 {
      filters.append("afade=t=in:st=0:d=\(request.fadeInSeconds)")
    }
    if request.fadeOutSeconds > 0 {
      let fadeDuration = min(request.fadeOutSeconds, duration)
      let start = max(0, duration - fadeDuration)
      filters.append("afade=t=out:st=\(start):d=\(fadeDuration)")
    }
    return filters
  }

  private static func formatSeconds(_ value: Double) -> String {
    String(format: "%.3f", value)
  }
}
