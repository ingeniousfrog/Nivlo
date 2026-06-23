import Foundation
import NivloDomain
import NivloImaging
import Testing

@Suite("FFmpeg capability detector")
struct FFmpegCapabilityDetectorTests {
  @Test("selects hardware codec only when the encoder is available")
  func detectsEncoders() async throws {
    let executable = FileManager.default.temporaryDirectory
      .appending(path: "\(UUID().uuidString)-ffmpeg")
    try Data(
      """
      #!/bin/sh
      echo ' V..... h264_videotoolbox VideoToolbox H.264'
      echo ' V..... libx264 H.264 software'
      """.utf8
    ).write(to: executable)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: executable.path
    )

    let capabilities = try await FFmpegCapabilityDetector(
      ffmpegExecutable: executable
    ).detect()
    let preset = VideoExportPreset.builtIn.first {
      $0.id == "h264-balanced"
    }!

    #expect(capabilities.videoEncoders.contains("h264_videotoolbox"))
    #expect(capabilities.codec(for: preset) == "h264_videotoolbox")
  }
}
