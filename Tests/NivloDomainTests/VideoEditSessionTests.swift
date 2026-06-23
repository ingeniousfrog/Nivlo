import Foundation
import NivloDomain
import Testing

@Suite("Video edit session")
struct VideoEditSessionTests {
  @Test("normalized visual crop converts to even source pixels")
  func normalizedCrop() {
    let crop = NormalizedCropRect(x: 0.1, y: 0.2, width: 0.5, height: 0.5)

    let pixels = VideoCropRect(
      normalized: crop,
      sourceWidth: 1_921,
      sourceHeight: 1_081
    )

    #expect(pixels.x.isMultiple(of: 2))
    #expect(pixels.y.isMultiple(of: 2))
    #expect(pixels.width.isMultiple(of: 2))
    #expect(pixels.height.isMultiple(of: 2))
    #expect(pixels.x + pixels.width <= 1_921)
    #expect(pixels.y + pixels.height <= 1_081)
  }

  @Test("video sessions persist trim audio and export settings")
  func codableSession() throws {
    let session = VideoEditSession(
      sourceURL: URL(filePath: "/tmp/source.mov"),
      durationSeconds: 20,
      startSeconds: 2,
      endSeconds: 18,
      normalizedCrop: NormalizedCropRect(x: 0.1, y: 0.1, width: 0.8, height: 0.8),
      volume: 0.8,
      fadeInSeconds: 1,
      fadeOutSeconds: 2,
      exportPresetID: "hevc-quality"
    )

    let data = try JSONEncoder().encode(session)
    let decoded = try JSONDecoder().decode(VideoEditSession.self, from: data)

    #expect(decoded == session)
  }

  @Test("decoded legacy sessions use safe defaults and normalize values")
  func decodedLegacySession() throws {
    let data = Data(
      """
      {
        "sourceURL": "file:///tmp/source.mov",
        "durationSeconds": 20,
        "startSeconds": -3,
        "endSeconds": 25,
        "normalizedCrop": {
          "x": -1,
          "y": 2,
          "width": 3,
          "height": -2
        },
        "transposeQuarterTurns": -1,
        "volume": 4
      }
      """.utf8
    )

    let session = try JSONDecoder().decode(VideoEditSession.self, from: data)

    #expect(session.startSeconds == 0)
    #expect(session.endSeconds == 20)
    #expect(session.normalizedCrop == NormalizedCropRect(x: 0, y: 0.99, width: 1, height: 0.01))
    #expect(session.transposeQuarterTurns == 3)
    #expect(session.volume == 2)
    #expect(session.fadeInSeconds == 0)
    #expect(session.exportPresetID == "h264-balanced")
    #expect(session.outputFormat == .mp4)
  }

  @Test("video presets declare hardware fallback codecs")
  func videoPresets() {
    let preset = VideoExportPreset.builtIn.first { $0.id == "h264-balanced" }

    #expect(preset?.softwareCodec == "libx264")
    #expect(preset?.hardwareCodec == "h264_videotoolbox")
    #expect(preset?.outputFormat == .mp4)
  }
}
