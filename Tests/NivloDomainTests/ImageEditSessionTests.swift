import NivloDomain
import Testing

@Suite("Image edit session")
struct ImageEditSessionTests {
  @Test("revert restores the state from when the editor opened")
  func revertRestoresInitialSnapshot() {
    let initial = ImageEditSnapshot(cropRect: .full)
    let edited = ImageEditSnapshot(
      cropRect: NormalizedCropRect(x: 0.1, y: 0.1, width: 0.7, height: 0.7),
      quarterTurns: 1,
      adjustments: ImageAdjustmentSettings(exposure: 0.4)
    )
    var session = ImageEditSession(initialSnapshot: initial)

    session.replaceCurrent(with: edited)
    session.revert()

    #expect(session.currentSnapshot == initial)
    #expect(!session.hasChanges)
  }

  @Test("rendering a preview does not redefine the revert baseline")
  func previewDoesNotChangeRevertBaseline() {
    let initial = ImageEditSnapshot(cropRect: .full)
    let edited = ImageEditSnapshot(quarterTurns: 2)
    var session = ImageEditSession(initialSnapshot: initial)

    session.replaceCurrent(with: edited)
    let previewSnapshot = session.currentSnapshot
    session.revert()

    #expect(previewSnapshot == edited)
    #expect(session.currentSnapshot == initial)
  }

  @Test("updates the current snapshot without mutating the initial snapshot")
  func updatesCurrentSnapshotImmutably() {
    let initial = ImageEditSnapshot(cropRect: .full)
    var session = ImageEditSession(initialSnapshot: initial)

    session.update { snapshot in
      snapshot.quarterTurns = 3
      snapshot.adjustments = ImageAdjustmentSettings(contrast: 0.2)
    }

    #expect(session.initialSnapshot == initial)
    #expect(session.currentSnapshot.quarterTurns == 3)
    #expect(session.currentSnapshot.adjustments.contrast == 0.2)
    #expect(session.hasChanges)
  }
}
