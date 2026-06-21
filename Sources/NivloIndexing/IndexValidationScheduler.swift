import Foundation
import NivloDomain

public struct IndexValidationSummary: Equatable, Sendable {
  public let validatedRootCount: Int
  public let failureCount: Int
  public let lastValidatedAt: Date?

  public init(
    validatedRootCount: Int,
    failureCount: Int,
    lastValidatedAt: Date?
  ) {
    self.validatedRootCount = validatedRootCount
    self.failureCount = failureCount
    self.lastValidatedAt = lastValidatedAt
  }
}

public actor IndexValidationScheduler {
  private let scanner: any DirectoryScanning
  private let now: @Sendable () -> Date
  private var task: Task<Void, Never>?
  public private(set) var lastSummary: IndexValidationSummary?

  public init(
    scanner: any DirectoryScanning,
    now: @escaping @Sendable () -> Date = Date.init
  ) {
    self.scanner = scanner
    self.now = now
  }

  deinit {
    task?.cancel()
  }

  public func validateNow(rootURLs: [URL]) async throws -> IndexValidationSummary {
    var validatedCount = 0
    var failureCount = 0
    for rootURL in rootURLs.map(\.standardizedFileURL) {
      do {
        _ = try await scanner.scan(rootURL: rootURL)
        validatedCount += 1
      } catch {
        failureCount += 1
      }
    }
    let summary = IndexValidationSummary(
      validatedRootCount: validatedCount,
      failureCount: failureCount,
      lastValidatedAt: rootURLs.isEmpty ? nil : now()
    )
    lastSummary = summary
    return summary
  }

  public func start(
    rootURLs: @escaping @Sendable () async -> [URL],
    intervalNanoseconds: UInt64 = 30 * 60 * 1_000_000_000
  ) {
    task?.cancel()
    task = Task { [weak self] in
      while !Task.isCancelled {
        do {
          try await Task.sleep(nanoseconds: intervalNanoseconds)
          guard let self else {
            return
          }
          _ = try? await self.validateNow(rootURLs: await rootURLs())
        } catch {
          return
        }
      }
    }
  }

  public func stop() {
    task?.cancel()
    task = nil
  }
}
