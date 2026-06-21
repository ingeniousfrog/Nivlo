import Foundation
import NivloDomain
import Testing

@testable import NivloIndexing

@Suite("Index validation scheduler")
struct IndexValidationSchedulerTests {
  @Test("validates every active root and records the latest validation time")
  func validatesRootsAndRecordsTime() async throws {
    let scanner = RecordingValidationScanner()
    let scheduler = IndexValidationScheduler(
      scanner: scanner,
      now: { Date(timeIntervalSince1970: 1234) }
    )
    let roots = [
      URL(filePath: "/tmp/first"),
      URL(filePath: "/tmp/second"),
    ]

    let summary = try await scheduler.validateNow(rootURLs: roots)
    let calls = await scanner.calls()

    #expect(calls == roots.map(\.standardizedFileURL))
    #expect(summary.validatedRootCount == 2)
    #expect(summary.lastValidatedAt == Date(timeIntervalSince1970: 1234))
  }

  @Test("continues validating other roots after one root fails")
  func isolatesRootValidationFailure() async throws {
    let first = URL(filePath: "/tmp/first")
    let second = URL(filePath: "/tmp/second")
    let scanner = RecordingValidationScanner(failingRoot: first.standardizedFileURL)
    let scheduler = IndexValidationScheduler(scanner: scanner)

    let summary = try await scheduler.validateNow(rootURLs: [first, second])
    let calls = await scanner.calls()

    #expect(calls == [first.standardizedFileURL, second.standardizedFileURL])
    #expect(summary.validatedRootCount == 1)
    #expect(summary.failureCount == 1)
  }
}

private actor RecordingValidationScanner: DirectoryScanning {
  private let failingRoot: URL?
  private var recordedCalls: [URL] = []

  init(failingRoot: URL? = nil) {
    self.failingRoot = failingRoot
  }

  func scan(rootURL: URL) async throws -> ScanSummary {
    recordedCalls.append(rootURL.standardizedFileURL)
    if rootURL.standardizedFileURL == failingRoot {
      throw ValidationFixtureError.failed
    }
    return ScanSummary(discoveredCount: 0, indexedCount: 0, removedCount: 0, skippedCount: 0)
  }

  func scan(scopeURL: URL, under rootURL: URL) async throws -> ScanSummary {
    try await scan(rootURL: rootURL)
  }

  func calls() -> [URL] {
    recordedCalls
  }
}

private enum ValidationFixtureError: Error {
  case failed
}
