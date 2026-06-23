import Foundation
import NivloDomain
import Testing

@Suite("Asset rename planning")
struct AssetRenamingTests {
  @Test("builds a same folder destination with a sanitized filename")
  func buildsDestination() throws {
    let asset = makeAsset(filename: "before.png")

    let plan = try AssetRenamer.plan(
      for: asset,
      proposedFilename: "  after.png  ",
      fileExists: { _ in false }
    )

    #expect(plan.sourceURL == asset.url.standardizedFileURL)
    #expect(plan.destinationURL.lastPathComponent == "after.png")
    #expect(plan.destinationURL.deletingLastPathComponent() == asset.url.deletingLastPathComponent())
    #expect(plan.filename == "after.png")
  }

  @Test("rejects empty path-like unchanged and extension-changing filenames")
  func rejectsInvalidNames() throws {
    let asset = makeAsset(filename: "before.png")

    #expect(throws: AssetRenameError.emptyFilename) {
      try AssetRenamer.plan(for: asset, proposedFilename: " ", fileExists: { _ in false })
    }
    #expect(throws: AssetRenameError.invalidFilename("nested/after.png")) {
      try AssetRenamer.plan(for: asset, proposedFilename: "nested/after.png", fileExists: { _ in false })
    }
    #expect(throws: AssetRenameError.unchangedFilename) {
      try AssetRenamer.plan(for: asset, proposedFilename: "before.png", fileExists: { _ in false })
    }
    #expect(throws: AssetRenameError.changedExtension(original: ".png", proposed: ".jpg")) {
      try AssetRenamer.plan(for: asset, proposedFilename: "after.jpg", fileExists: { _ in false })
    }
  }

  @Test("rejects a conflicting destination")
  func rejectsExistingDestination() throws {
    let asset = makeAsset(filename: "before.png")

    #expect(throws: AssetRenameError.destinationExists(asset.url.deletingLastPathComponent().appending(path: "after.png"))) {
      try AssetRenamer.plan(for: asset, proposedFilename: "after.png", fileExists: { _ in true })
    }
  }
}

private func makeAsset(filename: String) -> ImageAsset {
  let url = URL(filePath: "/tmp/NivloRenameTests").appending(path: filename)
  return ImageAsset(
    id: AssetID(volumeIdentifier: "volume", fileIdentifier: "file"),
    url: url,
    filename: filename,
    contentType: "public.png",
    fileSize: 1_024,
    createdAt: Date(timeIntervalSince1970: 1_700_000_000),
    modifiedAt: Date(timeIntervalSince1970: 1_700_000_100),
    pixelWidth: 100,
    pixelHeight: 100
  )
}
