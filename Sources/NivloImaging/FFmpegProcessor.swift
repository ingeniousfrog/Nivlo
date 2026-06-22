import Foundation
import NivloDomain

public enum FFmpegProcessorError: Error, LocalizedError, Sendable {
  case ffmpegUnavailable
  case exportFailed(String)

  public var errorDescription: String? {
    switch self {
    case .ffmpegUnavailable:
      "ffmpeg is not installed yet."
    case .exportFailed(let detail):
      detail
    }
  }
}

public struct FFmpegProcessor: Sendable {
  private let runner: ExternalProcessRunner
  private let ffmpegExecutable: URL?

  public init(
    ffmpegExecutable: URL? = nil,
    runner: ExternalProcessRunner = ExternalProcessRunner()
  ) {
    self.ffmpegExecutable = ffmpegExecutable
    self.runner = runner
  }

  public func export(
    request: VideoEditRequest,
    progress: (@Sendable (FFmpegExportProgress) -> Void)? = nil
  ) async throws -> URL {
    let ffmpeg: URL?
    if let ffmpegExecutable {
      ffmpeg = ffmpegExecutable
    } else {
      ffmpeg = await MainActor.run { ToolBootstrapper.shared.manifest.ffmpegURL }
    }
    guard let ffmpeg else {
      throw FFmpegProcessorError.ffmpegUnavailable
    }

    let command = FFmpegCommandBuilder.build(request: request, ffmpegExecutable: ffmpeg)
    if let parent = request.outputURL.deletingLastPathComponent() as URL? {
      try? FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    }
    if FileManager.default.fileExists(atPath: request.outputURL.path) {
      try FileManager.default.removeItem(at: request.outputURL)
    }

    try await runWithProgress(
      command: command,
      totalSeconds: request.trimRange.endSeconds - request.trimRange.startSeconds,
      progress: progress
    )

    guard FileManager.default.fileExists(atPath: request.outputURL.path) else {
      throw FFmpegProcessorError.exportFailed("ffmpeg did not produce an output file.")
    }
    return request.outputURL
  }

  private func runWithProgress(
    command: FFmpegCommandBuilder,
    totalSeconds: Double,
    progress: (@Sendable (FFmpegExportProgress) -> Void)?
  ) async throws {
    try await withCheckedThrowingContinuation { continuation in
      DispatchQueue.global(qos: .userInitiated).async {
        do {
          try Self.runSynchronously(
            command: command,
            totalSeconds: totalSeconds,
            progress: progress
          )
          continuation.resume()
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private static func runSynchronously(
    command: FFmpegCommandBuilder,
    totalSeconds: Double,
    progress: (@Sendable (FFmpegExportProgress) -> Void)?
  ) throws {
    guard FileManager.default.isExecutableFile(atPath: command.executable.path) else {
      throw FFmpegProcessorError.ffmpegUnavailable
    }

    let process = Process()
    process.executableURL = command.executable
    process.arguments = command.arguments

    let stderrPipe = Pipe()
    process.standardOutput = Pipe()
    process.standardError = stderrPipe

    try process.run()

    let handle = stderrPipe.fileHandleForReading
    var buffer = Data()
    while process.isRunning {
      let chunk = handle.availableData
      if chunk.isEmpty {
        Thread.sleep(forTimeInterval: 0.05)
        continue
      }
      buffer.append(chunk)
      if let text = String(data: buffer, encoding: .utf8) {
        if let seconds = parseProcessedSeconds(from: text) {
          progress?(FFmpegExportProgress(
            processedSeconds: seconds,
            totalSeconds: totalSeconds > 0 ? totalSeconds : nil
          ))
        }
        if text.contains("\n") || text.contains("\r") {
          buffer = Data()
        }
      }
    }

    let trailing = handle.readDataToEndOfFile()
    if !trailing.isEmpty, let text = String(data: trailing, encoding: .utf8),
      let seconds = parseProcessedSeconds(from: text)
    {
      progress?(FFmpegExportProgress(
        processedSeconds: seconds,
        totalSeconds: totalSeconds > 0 ? totalSeconds : nil
      ))
    }

    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
      let stderr = String(data: trailing, encoding: .utf8) ?? "ffmpeg failed."
      throw FFmpegProcessorError.exportFailed(stderr)
    }
  }

  private static func parseProcessedSeconds(from text: String) -> Double? {
    guard let range = text.range(of: "time=") else {
      return nil
    }
    let suffix = text[range.upperBound...]
    let token = suffix.prefix(while: { $0 != " " && $0 != "\n" && $0 != "\r" })
    let parts = token.split(separator: ":")
    guard parts.count == 3,
      let hours = Double(parts[0]),
      let minutes = Double(parts[1]),
      let seconds = Double(parts[2])
    else {
      return nil
    }
    return hours * 3_600 + minutes * 60 + seconds
  }
}
