import Foundation
import NivloDomain
import NivloPersistence
import Testing

@Suite("Edit session store")
struct EditSessionStoreTests {
  @Test("saves and reopens image and video sessions")
  func savesSessions() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = FileEditSessionStore(baseDirectory: directory)
    let assetID = AssetID(volumeIdentifier: "volume/one", fileIdentifier: "file:two")
    let image = ImageEditSnapshot(
      adjustments: ImageAdjustmentSettings(exposure: 0.4)
    )
    let video = VideoEditSession(
      sourceURL: URL(filePath: "/tmp/video.mov"),
      durationSeconds: 12,
      startSeconds: 1,
      endSeconds: 10
    )

    try await store.saveImageSession(image, for: assetID)
    try await store.saveVideoSession(video, for: assetID)

    #expect(try await store.imageSession(for: assetID) == image)
    #expect(try await store.videoSession(for: assetID) == video)
  }

  @Test("custom presets persist atomically")
  func savesPresets() async throws {
    let directory = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    let store = FileEditSessionStore(baseDirectory: directory)
    let preset = ImageAdjustmentPreset(
      id: UUID().uuidString,
      name: "My preset",
      settings: ImageAdjustmentSettings(vibrance: 0.25)
    )

    try await store.saveAdjustmentPresets([preset])

    #expect(try await store.adjustmentPresets() == [preset])
  }
}
