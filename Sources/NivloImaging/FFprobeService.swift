import Foundation
import NivloDomain

public enum FFprobeServiceError: Error, LocalizedError, Sendable {
  case ffprobeUnavailable
  case invalidResponse

  public var errorDescription: String? {
    switch self {
    case .ffprobeUnavailable:
      "ffprobe is not installed yet."
    case .invalidResponse:
      "ffprobe returned an invalid response."
    }
  }
}

public struct FFprobeService: Sendable {
  private let runner: ExternalProcessRunner
  private let ffprobeExecutable: URL?

  public init(
    ffprobeExecutable: URL? = nil,
    runner: ExternalProcessRunner = ExternalProcessRunner()
  ) {
    self.ffprobeExecutable = ffprobeExecutable
    self.runner = runner
  }

  public func probe(sourceURL: URL) async throws -> VideoProbeInfo {
    let ffprobe: URL?
    if let ffprobeExecutable {
      ffprobe = ffprobeExecutable
    } else {
      ffprobe = await MainActor.run { ToolBootstrapper.shared.manifest.ffprobeURL }
    }
    guard let ffprobe else {
      throw FFprobeServiceError.ffprobeUnavailable
    }

    let result = try await runner.run(
      ExternalProcessRequest(
        executable: ffprobe,
        arguments: [
          "-v", "error",
          "-print_format", "json",
          "-show_format",
          "-show_streams",
          sourceURL.path,
        ]
      )
    )
    return try parseProbeJSON(result.stdout)
  }

  private func parseProbeJSON(_ json: String) throws -> VideoProbeInfo {
    guard let data = json.data(using: .utf8),
      let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    else {
      throw FFprobeServiceError.invalidResponse
    }

    let format = root["format"] as? [String: Any]
    let duration = Double(format?["duration"] as? String ?? "") ?? 0
    let streams = root["streams"] as? [[String: Any]] ?? []
    let videoStream = streams.first { ($0["codec_type"] as? String) == "video" }
    let audioStream = streams.first { ($0["codec_type"] as? String) == "audio" }
    let hasAudio = audioStream != nil
    let width = videoStream?["width"] as? Int ?? 0
    let height = videoStream?["height"] as? Int ?? 0
    let frameRate = parseFrameRate(videoStream?["r_frame_rate"] as? String)

    return VideoProbeInfo(
      durationSeconds: duration,
      width: width,
      height: height,
      frameRate: frameRate,
      hasAudio: hasAudio,
      videoCodec: videoStream?["codec_name"] as? String,
      audioCodec: audioStream?["codec_name"] as? String
    )
  }

  private func parseFrameRate(_ value: String?) -> Double {
    guard let value, value.contains("/") else {
      return Double(value ?? "") ?? 0
    }
    let parts = value.split(separator: "/")
    guard parts.count == 2,
      let numerator = Double(parts[0]),
      let denominator = Double(parts[1]),
      denominator != 0
    else {
      return 0
    }
    return numerator / denominator
  }
}
