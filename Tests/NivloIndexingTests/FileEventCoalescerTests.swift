import Foundation
import Testing

@testable import NivloIndexing

@Suite("File event coalescer")
struct FileEventCoalescerTests {
  @Test("coalesces file changes to their containing directories")
  func coalescesToDirectories() {
    let root = URL(filePath: "/Library/Images")
    let events = [
      FileSystemEvent(url: root.appending(path: "one/a.png")),
      FileSystemEvent(url: root.appending(path: "two/b.png")),
    ]

    let result = FileEventCoalescer().coalesce(events, libraryRoot: root)

    #expect(
      paths(result.directories)
        == paths([
          root.appending(path: "one"),
          root.appending(path: "two"),
        ]))
  }

  @Test("prefers an ancestor directory over many nested children")
  func minimizesNestedDirectories() {
    let root = URL(filePath: "/Library/Images")
    let parent = root.appending(path: "Project")
    let events = [
      FileSystemEvent(url: parent),
      FileSystemEvent(url: parent.appending(path: "icons/a.png")),
      FileSystemEvent(url: parent.appending(path: "screens/b.png")),
    ]

    let result = FileEventCoalescer().coalesce(events, libraryRoot: root)

    #expect(paths(result.directories) == paths([parent]))
  }

  @Test("ignores events outside the authorized root")
  func ignoresOutsideRoot() {
    let root = URL(filePath: "/Library/Images")
    let events = [
      FileSystemEvent(url: URL(filePath: "/tmp/outside.png")),
      FileSystemEvent(url: root.appending(path: "inside.png")),
    ]

    let result = FileEventCoalescer().coalesce(events, libraryRoot: root)

    #expect(paths(result.directories) == paths([root]))
  }

  @Test("carries full validation signals through the batch")
  func propagatesValidationSignal() {
    let root = URL(filePath: "/Library/Images")
    let events = [
      FileSystemEvent(url: root.appending(path: "a.png")),
      FileSystemEvent(
        url: root.appending(path: "ExternalDrive"),
        requiresFullValidation: true
      ),
    ]

    let result = FileEventCoalescer().coalesce(events, libraryRoot: root)

    #expect(result.requiresFullValidation)
  }
}

private func paths(_ urls: [URL]) -> [String] {
  urls.map(\.standardizedFileURL.path).sorted()
}
