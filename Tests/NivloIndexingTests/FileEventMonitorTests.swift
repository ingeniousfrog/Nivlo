import Foundation
import NivloDomain
import Testing

@testable import NivloIndexing

@Suite("File event monitor")
struct FileEventMonitorTests {
  @Test("starts one watcher for each active root")
  func startsWatchersForActiveRoots() async throws {
    let watcher = CapturingFileEventWatcher()
    let scanner = RecordingDirectoryScanner()
    let monitor = LibraryRootFileEventMonitor(
      watcher: watcher,
      scanner: scanner,
      debounceNanoseconds: 1_000_000
    )
    let firstRoot = URL(filePath: "/tmp/nivlo-first")
    let secondRoot = URL(filePath: "/tmp/nivlo-second")

    try await monitor.start(rootURLs: [firstRoot, secondRoot])
    let watchedRoots = watcher.watchedRoots()

    #expect(watchedRoots == [firstRoot, secondRoot])
  }

  @Test("coalesces rapid file events into scoped rescans")
  func coalescesRapidEventsIntoScopedRescans() async throws {
    let watcher = CapturingFileEventWatcher()
    let scanner = RecordingDirectoryScanner()
    let monitor = LibraryRootFileEventMonitor(
      watcher: watcher,
      scanner: scanner,
      debounceNanoseconds: 1_000_000
    )
    let root = URL(filePath: "/tmp/nivlo-library")
    let icons = root.appending(path: "icons", directoryHint: .isDirectory)
    try await monitor.start(rootURLs: [root])

    watcher.emit(
      [
        FileSystemEvent(url: icons.appending(path: "first.png")),
        FileSystemEvent(url: icons.appending(path: "second.png")),
      ],
      for: root
    )
    try await Task.sleep(nanoseconds: 200_000_000)
    let calls = await scanner.calls()

    #expect(calls == [.scoped(scopeURL: icons, rootURL: root)])
  }

  @Test("full validation events rescan the whole root")
  func fullValidationEventsRescanRoot() async throws {
    let watcher = CapturingFileEventWatcher()
    let scanner = RecordingDirectoryScanner()
    let monitor = LibraryRootFileEventMonitor(
      watcher: watcher,
      scanner: scanner,
      debounceNanoseconds: 1_000_000
    )
    let root = URL(filePath: "/tmp/nivlo-library")
    try await monitor.start(rootURLs: [root])

    watcher.emit(
      [FileSystemEvent(url: root, requiresFullValidation: true)],
      for: root
    )
    try await Task.sleep(nanoseconds: 200_000_000)
    let calls = await scanner.calls()

    #expect(calls == [.root(root)])
  }
}

private final class CapturingFileEventWatcher: FileEventWatching, @unchecked Sendable {
  private let lock = NSLock()
  private var handlers: [URL: ([FileSystemEvent]) -> Void] = [:]

  func start(
    rootURL: URL,
    handler: @escaping ([FileSystemEvent]) -> Void
  ) throws -> any FileEventWatch {
    lock.lock()
    defer { lock.unlock() }
    handlers[rootURL.standardizedFileURL] = handler
    return CapturingFileEventWatch()
  }

  func watchedRoots() -> [URL] {
    lock.lock()
    defer { lock.unlock() }
    return handlers.keys.sorted { $0.path < $1.path }
  }

  func emit(_ events: [FileSystemEvent], for rootURL: URL) {
    lock.lock()
    let handler = handlers[rootURL.standardizedFileURL]
    lock.unlock()
    handler?(events)
  }
}

private struct CapturingFileEventWatch: FileEventWatch {
  func stop() {}
}

private actor RecordingDirectoryScanner: DirectoryScanning {
  private var recordedCalls: [ScanCall] = []

  func scan(rootURL: URL) async throws -> ScanSummary {
    recordedCalls.append(.root(rootURL.standardizedFileURL))
    return emptySummary
  }

  func scan(scopeURL: URL, under rootURL: URL) async throws -> ScanSummary {
    recordedCalls.append(
      .scoped(
        scopeURL: scopeURL.standardizedFileURL,
        rootURL: rootURL.standardizedFileURL
      )
    )
    return emptySummary
  }

  func calls() -> [ScanCall] {
    recordedCalls
  }

  private var emptySummary: ScanSummary {
    ScanSummary(discoveredCount: 0, indexedCount: 0, removedCount: 0, skippedCount: 0)
  }
}

private enum ScanCall: Equatable {
  case root(URL)
  case scoped(scopeURL: URL, rootURL: URL)
}
