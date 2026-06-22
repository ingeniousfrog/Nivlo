import Foundation
import ImageIO
import NivloDomain
import Testing
import UniformTypeIdentifiers

@testable import NivloIndexing

@Suite("Directory scanner")
struct DirectoryScannerTests {
  @Test("indexes supported images recursively and ignores unrelated files")
  func indexesImagesRecursively() async throws {
    let fixture = try TemporaryDirectory()
    let nested = fixture.url.appending(path: "project/assets", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: nested,
      withIntermediateDirectories: true
    )
    try makeImage(at: fixture.url.appending(path: "cover.png"))
    try makeImage(at: nested.appending(path: "photo.jpg"))
    try Data("notes".utf8).write(to: fixture.url.appending(path: "notes.txt"))
    let repository = InMemoryAssetRepository()
    let scanner = DirectoryScanner(repository: repository)

    let summary = try await scanner.scan(rootURL: fixture.url)
    let assets = await repository.assets()

    #expect(summary.discoveredCount == 2)
    #expect(summary.indexedCount == 2)
    #expect(summary.skippedCount == 1)
    #expect(assets.map(\.filename).sorted() == ["cover.png", "photo.jpg"])
    #expect(assets.allSatisfy { $0.pixelWidth == 2 && $0.pixelHeight == 2 })
  }

  @Test("rescanning the same directory is idempotent")
  func rescanIsIdempotent() async throws {
    let fixture = try TemporaryDirectory()
    try makeImage(at: fixture.url.appending(path: "asset.png"))
    let repository = InMemoryAssetRepository()
    let scanner = DirectoryScanner(repository: repository)

    _ = try await scanner.scan(rootURL: fixture.url)
    let firstAssets = await repository.assets()
    let secondSummary = try await scanner.scan(rootURL: fixture.url)
    let secondAssets = await repository.assets()

    #expect(firstAssets == secondAssets)
    #expect(secondSummary.indexedCount == 1)
    #expect(secondSummary.removedCount == 0)
  }

  @Test("rescanning removes missing assets within the scanned root")
  func removesMissingAssets() async throws {
    let fixture = try TemporaryDirectory()
    let firstURL = fixture.url.appending(path: "first.png")
    let secondURL = fixture.url.appending(path: "second.png")
    try makeImage(at: firstURL)
    try makeImage(at: secondURL)
    let repository = InMemoryAssetRepository()
    let scanner = DirectoryScanner(repository: repository)
    _ = try await scanner.scan(rootURL: fixture.url)
    try FileManager.default.removeItem(at: firstURL)

    let summary = try await scanner.scan(rootURL: fixture.url)
    let assets = await repository.assets()

    #expect(summary.removedCount == 1)
    #expect(assets.map(\.filename) == ["second.png"])
  }

  @Test("scoped scans update only the affected directory")
  func scopedScanUpdatesOnlyAffectedDirectory() async throws {
    let fixture = try TemporaryDirectory()
    let icons = fixture.url.appending(path: "icons", directoryHint: .isDirectory)
    let logos = fixture.url.appending(path: "logos", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(at: icons, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: logos, withIntermediateDirectories: true)
    let oldIcon = icons.appending(path: "old.png")
    let newIcon = icons.appending(path: "new.png")
    let logo = logos.appending(path: "keep.png")
    try makeImage(at: oldIcon)
    try makeImage(at: logo)
    let repository = InMemoryAssetRepository()
    let scanner = DirectoryScanner(repository: repository)
    _ = try await scanner.scan(rootURL: fixture.url)
    try FileManager.default.removeItem(at: oldIcon)
    try makeImage(at: newIcon)

    let summary = try await scanner.scan(scopeURL: icons, under: fixture.url)
    let assets = await repository.assets()

    #expect(summary.discoveredCount == 1)
    #expect(summary.removedCount == 1)
    #expect(assets.map(\.filename).sorted() == ["keep.png", "new.png"])
  }

  @Test("scoped scan rejects a scope outside the library root")
  func scopedScanRejectsExternalScope() async throws {
    let fixture = try TemporaryDirectory()
    let external = try TemporaryDirectory()
    let scanner = DirectoryScanner(repository: InMemoryAssetRepository())

    await #expect(throws: DirectoryScannerError.invalidRoot(external.url)) {
      try await scanner.scan(scopeURL: external.url, under: fixture.url)
    }
  }

  @Test("rejects a scan root that is not a directory")
  func rejectsFileRoot() async throws {
    let fixture = try TemporaryDirectory()
    let fileURL = fixture.url.appending(path: "asset.png")
    try makeImage(at: fileURL)
    let scanner = DirectoryScanner(repository: InMemoryAssetRepository())

    await #expect(throws: DirectoryScannerError.invalidRoot(fileURL)) {
      try await scanner.scan(rootURL: fileURL)
    }
  }

  @Test("partial scans preserve assets hidden by transient enumeration errors")
  func partialScanPreservesExistingAssets() async throws {
    let fixture = try TemporaryDirectory()
    let visibleURL = fixture.url.appending(path: "visible.png")
    let temporarilyHiddenURL = fixture.url.appending(path: "hidden.png")
    try makeImage(at: visibleURL)
    try makeImage(at: temporarilyHiddenURL)
    let repository = InMemoryAssetRepository()
    let completeScanner = DirectoryScanner(repository: repository)
    _ = try await completeScanner.scan(rootURL: fixture.url)
    let partialScanner = DirectoryScanner(
      repository: repository,
      contentLister: DirectoryContentListerStub(
        result: DirectoryListing(
          urls: [visibleURL],
          issueCount: 1
        )
      )
    )

    let summary = try await partialScanner.scan(rootURL: fixture.url)
    let assets = await repository.assets()

    #expect(summary.issueCount == 1)
    #expect(summary.removedCount == 0)
    #expect(assets.map(\.filename).sorted() == ["hidden.png", "visible.png"])
  }

  @Test("missing stable identity preserves existing assets")
  func missingIdentityPreservesExistingAssets() async throws {
    let fixture = try TemporaryDirectory()
    let visibleURL = fixture.url.appending(path: "visible.png")
    let hiddenURL = fixture.url.appending(path: "hidden.png")
    try makeImage(at: visibleURL)
    try makeImage(at: hiddenURL)
    let repository = InMemoryAssetRepository()
    _ = try await DirectoryScanner(repository: repository).scan(rootURL: fixture.url)
    let partialScanner = DirectoryScanner(
      repository: repository,
      contentLister: DirectoryContentListerStub(
        result: DirectoryListing(urls: [visibleURL], issueCount: 0)
      ),
      resourceReader: FileResourceReaderStub(
        snapshots: [
          visibleURL: FileResourceSnapshot(
            isRegularFile: true,
            contentType: .png,
            fileSize: 1,
            createdAt: nil,
            modifiedAt: nil,
            fileIdentifier: nil,
            volumeIdentifier: "volume"
          )
        ]
      )
    )

    let summary = try await partialScanner.scan(rootURL: fixture.url)
    let assets = await repository.assets()

    #expect(summary.issueCount == 1)
    #expect(summary.removedCount == 0)
    #expect(assets.map(\.filename).sorted() == ["hidden.png", "visible.png"])
  }

  @Test("missing content type preserves existing assets")
  func missingContentTypePreservesExistingAssets() async throws {
    let fixture = try TemporaryDirectory()
    let visibleURL = fixture.url.appending(path: "visible.png")
    let hiddenURL = fixture.url.appending(path: "hidden.png")
    try makeImage(at: visibleURL)
    try makeImage(at: hiddenURL)
    let repository = InMemoryAssetRepository()
    _ = try await DirectoryScanner(repository: repository).scan(rootURL: fixture.url)
    let partialScanner = DirectoryScanner(
      repository: repository,
      contentLister: DirectoryContentListerStub(
        result: DirectoryListing(urls: [visibleURL], issueCount: 0)
      ),
      resourceReader: FileResourceReaderStub(
        snapshots: [
          visibleURL: FileResourceSnapshot(
            isRegularFile: true,
            contentType: nil,
            fileSize: 1,
            createdAt: nil,
            modifiedAt: nil,
            fileIdentifier: "file",
            volumeIdentifier: "volume"
          )
        ]
      )
    )

    let summary = try await partialScanner.scan(rootURL: fixture.url)
    let assets = await repository.assets()

    #expect(summary.issueCount == 1)
    #expect(summary.removedCount == 0)
    #expect(assets.map(\.filename).sorted() == ["hidden.png", "visible.png"])
  }

  @Test("indexes supported videos as visual assets")
  func indexesSupportedVideos() async throws {
    let fixture = try TemporaryDirectory()
    let videoURL = fixture.url.appending(path: "clip.mov")
    let textURL = fixture.url.appending(path: "notes.txt")
    try Data().write(to: videoURL)
    try Data().write(to: textURL)
    let repository = InMemoryAssetRepository()
    let scanner = DirectoryScanner(
      repository: repository,
      contentLister: DirectoryContentListerStub(
        result: DirectoryListing(urls: [videoURL, textURL], issueCount: 0)
      ),
      resourceReader: FileResourceReaderStub(
        snapshots: [
          videoURL: FileResourceSnapshot(
            isRegularFile: true,
            contentType: .quickTimeMovie,
            fileSize: 1_024,
            createdAt: nil,
            modifiedAt: nil,
            fileIdentifier: "video",
            volumeIdentifier: "volume"
          ),
          textURL: FileResourceSnapshot(
            isRegularFile: true,
            contentType: .plainText,
            fileSize: 128,
            createdAt: nil,
            modifiedAt: nil,
            fileIdentifier: "text",
            volumeIdentifier: "volume"
          ),
        ]
      )
    )

    let summary = try await scanner.scan(rootURL: fixture.url)
    let assets = await repository.assets()

    #expect(summary.discoveredCount == 1)
    #expect(summary.skippedCount == 1)
    #expect(assets.map(\.filename) == ["clip.mov"])
  }

  @Test("an unhidden asset returns after a scoped rescan")
  func unhiddenAssetReturnsAfterScopedRescan() async throws {
    let fixture = try TemporaryDirectory()
    let nestedURL = fixture.url.appending(path: "nested", directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: nestedURL,
      withIntermediateDirectories: true
    )
    let imageURL = nestedURL.appending(path: "restored.png")
    try makeImage(at: imageURL)
    let repository = InMemoryAssetRepository()
    let scanner = DirectoryScanner(repository: repository)
    _ = try await scanner.scan(rootURL: fixture.url)
    let asset = try #require(await repository.assets().first)

    await repository.hideAsset(asset)
    await repository.unhideAsset(at: imageURL)
    _ = try await scanner.scan(scopeURL: nestedURL, under: fixture.url)

    #expect(await repository.assets().map(\.url) == [imageURL.standardizedFileURL])
  }

  @Test("reports progressive batches while indexing a large folder")
  func reportsProgressiveBatches() async throws {
    let fixture = try TemporaryDirectory()
    for index in 0..<5 {
      try makeImage(at: fixture.url.appending(path: "\(index).png"))
    }
    let repository = InMemoryAssetRepository()
    let scanner = DirectoryScanner(repository: repository, batchSize: 2)
    let progress = ProgressRecorder()

    _ = try await scanner.scan(rootURL: fixture.url) { update in
      await progress.append(update)
    }

    #expect(await progress.values.map(\.indexedCount) == [2, 4, 5])
    #expect(await repository.assets().count == 5)
  }
}

private struct DirectoryContentListerStub: DirectoryContentListing {
  let result: DirectoryListing

  func contents(of rootURL: URL, resourceKeys: [URLResourceKey]) throws
    -> DirectoryListing
  {
    result
  }
}

private struct FileResourceReaderStub: FileResourceReading {
  let snapshots: [URL: FileResourceSnapshot]

  func snapshot(for url: URL, keys: Set<URLResourceKey>) throws
    -> FileResourceSnapshot
  {
    guard let snapshot = snapshots[url] else {
      throw FixtureError.couldNotCreateImage
    }
    return snapshot
  }
}

private struct TemporaryDirectory {
  let url: URL

  init() throws {
    url = FileManager.default.temporaryDirectory
      .appending(path: UUID().uuidString, directoryHint: .isDirectory)
    try FileManager.default.createDirectory(
      at: url,
      withIntermediateDirectories: true
    )
  }
}

private func makeImage(at url: URL) throws {
  guard
    let destination = CGImageDestinationCreateWithURL(
      url as CFURL,
      UTType(filenameExtension: url.pathExtension)?.identifier as CFString?
        ?? UTType.png.identifier as CFString,
      1,
      nil
    ),
    let context = CGContext(
      data: nil,
      width: 2,
      height: 2,
      bitsPerComponent: 8,
      bytesPerRow: 8,
      space: CGColorSpaceCreateDeviceRGB(),
      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ),
    let image = context.makeImage()
  else {
    throw FixtureError.couldNotCreateImage
  }

  CGImageDestinationAddImage(destination, image, nil)
  guard CGImageDestinationFinalize(destination) else {
    throw FixtureError.couldNotCreateImage
  }
}

private enum FixtureError: Error {
  case couldNotCreateImage
}

private actor ProgressRecorder {
  private(set) var values: [ScanProgress] = []

  func append(_ progress: ScanProgress) {
    values.append(progress)
  }
}
