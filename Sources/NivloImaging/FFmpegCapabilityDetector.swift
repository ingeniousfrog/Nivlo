import Foundation
import NivloDomain

public struct FFmpegCapabilities: Equatable, Sendable {
  public let videoEncoders: Set<String>

  public init(videoEncoders: Set<String>) {
    self.videoEncoders = videoEncoders
  }

  public func codec(for preset: VideoExportPreset) -> String {
    guard
      let hardwareCodec = preset.hardwareCodec,
      videoEncoders.contains(hardwareCodec)
    else {
      return preset.softwareCodec
    }
    return hardwareCodec
  }
}

public enum FFmpegCapabilityDetectorError: Error, LocalizedError, Sendable {
  case ffmpegUnavailable

  public var errorDescription: String? {
    "FFmpeg is unavailable for codec capability detection."
  }
}

public struct FFmpegCapabilityDetector: Sendable {
  private let ffmpegExecutable: URL?
  private let runner: ExternalProcessRunner

  public init(
    ffmpegExecutable: URL? = nil,
    runner: ExternalProcessRunner = ExternalProcessRunner()
  ) {
    self.ffmpegExecutable = ffmpegExecutable
    self.runner = runner
  }

  public func detect() async throws -> FFmpegCapabilities {
    let executable: URL?
    if let ffmpegExecutable {
      executable = ffmpegExecutable
    } else {
      executable = await MainActor.run {
        ToolBootstrapper.shared.manifest.ffmpegURL
      }
    }
    guard let executable else {
      throw FFmpegCapabilityDetectorError.ffmpegUnavailable
    }
    let result = try await runner.run(
      ExternalProcessRequest(
        executable: executable,
        arguments: ["-hide_banner", "-encoders"],
        timeoutSeconds: 15
      )
    )
    let text = result.stdout + "\n" + result.stderr
    let encoders = Set<String>(
      text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
        let fields = line.split(whereSeparator: \.isWhitespace)
        guard
          fields.count >= 2,
          fields[0].contains("V")
        else {
          return nil
        }
        return String(fields[1])
      }
    )
    return FFmpegCapabilities(videoEncoders: encoders)
  }
}
