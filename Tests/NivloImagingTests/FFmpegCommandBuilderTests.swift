import Foundation
import NivloDomain
import Testing

@testable import NivloImaging

@Suite("FFmpeg command builder")
struct FFmpegCommandBuilderTests {
  @Test("builds trim and scale command")
  func buildsTrimAndScaleCommand() {
    let request = VideoEditRequest(
      sourceURL: URL(filePath: "/tmp/input.mp4"),
      outputURL: URL(filePath: "/tmp/output.mp4"),
      trimRange: VideoTrimRange(
        startSeconds: 1,
        endSeconds: 5,
        durationSeconds: 10
      ),
      cropRect: VideoCropRect(x: 10, y: 20, width: 640, height: 360),
      scaleWidth: 1280,
      scaleHeight: 720,
      transposeQuarterTurns: 1,
      outputFPS: 30,
      crf: 24
    )
    let command = FFmpegCommandBuilder.build(
      request: request,
      ffmpegExecutable: URL(filePath: "/usr/local/bin/ffmpeg")
    )
    #expect(command.arguments.contains("-ss"))
    #expect(command.arguments.joined(separator: " ").contains("crop=640:360:10:20"))
    #expect(command.arguments.joined(separator: " ").contains("scale=1280:720"))
    #expect(command.arguments.joined(separator: " ").contains("transpose=1"))
    #expect(command.arguments.joined(separator: " ").contains("fps=30.0"))
  }

  @Test("builds audio extract command")
  func buildsAudioExtractCommand() {
    let request = VideoEditRequest(
      sourceURL: URL(filePath: "/tmp/input.mp4"),
      outputURL: URL(filePath: "/tmp/output.m4a"),
      trimRange: VideoTrimRange(
        startSeconds: 0,
        endSeconds: 3,
        durationSeconds: 3
      ),
      extractAudioOnly: true,
      audioFormat: .m4a
    )
    let command = FFmpegCommandBuilder.buildAudioExtract(
      request: request,
      ffmpegExecutable: URL(filePath: "/usr/local/bin/ffmpeg")
    )
    #expect(command.arguments.contains("-vn"))
    #expect(command.arguments.contains("-c:a"))
    #expect(command.arguments.contains("aac"))
  }

  @Test("builds volume fades and a hardware codec preset")
  func buildsAudioAdjustmentsAndHardwareCodec() {
    let request = VideoEditRequest(
      sourceURL: URL(filePath: "/tmp/input.mp4"),
      outputURL: URL(filePath: "/tmp/output.mp4"),
      trimRange: VideoTrimRange(
        startSeconds: 2,
        endSeconds: 12,
        durationSeconds: 20
      ),
      videoCodec: "h264_videotoolbox",
      volume: 0.75,
      fadeInSeconds: 1.5,
      fadeOutSeconds: 2
    )

    let command = FFmpegCommandBuilder.build(
      request: request,
      ffmpegExecutable: URL(filePath: "/usr/local/bin/ffmpeg")
    )
    let joined = command.arguments.joined(separator: " ")

    #expect(joined.contains("-c:v h264_videotoolbox"))
    #expect(joined.contains("volume=0.75"))
    #expect(joined.contains("afade=t=in:st=0:d=1.5"))
    #expect(joined.contains("afade=t=out:st=8.0:d=2.0"))
  }
}
