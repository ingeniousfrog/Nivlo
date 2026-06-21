import Foundation

public struct FileSystemEvent: Equatable, Sendable {
  public let url: URL
  public let requiresFullValidation: Bool

  public init(url: URL, requiresFullValidation: Bool = false) {
    self.url = url.standardizedFileURL
    self.requiresFullValidation = requiresFullValidation
  }
}

public struct CoalescedFileEvents: Equatable, Sendable {
  public let directories: [URL]
  public let requiresFullValidation: Bool

  public init(
    directories: [URL],
    requiresFullValidation: Bool
  ) {
    self.directories = directories.map(\.standardizedFileURL)
      .sorted { $0.path < $1.path }
    self.requiresFullValidation = requiresFullValidation
  }
}

public struct FileEventCoalescer: Sendable {
  public init() {}

  public func coalesce(
    _ events: [FileSystemEvent],
    libraryRoot: URL
  ) -> CoalescedFileEvents {
    let root = libraryRoot.standardizedFileURL
    let relevantEvents = events.filter { $0.url.isContained(in: root) }
    let changedDirectories =
      relevantEvents
      .map { candidateDirectory(for: $0.url, libraryRoot: root) }
    let minimized = minimize(changedDirectories, libraryRoot: root)
    return CoalescedFileEvents(
      directories: minimized,
      requiresFullValidation: relevantEvents.contains {
        $0.requiresFullValidation
      }
    )
  }

  private func candidateDirectory(
    for url: URL,
    libraryRoot: URL
  ) -> URL {
    if url.path == libraryRoot.path {
      return libraryRoot
    }
    let hasExtension = !url.pathExtension.isEmpty
    let directory = hasExtension ? url.deletingLastPathComponent() : url
    return directory.isContained(in: libraryRoot) ? directory : libraryRoot
  }

  private func minimize(
    _ directories: [URL],
    libraryRoot: URL
  ) -> [URL] {
    let unique = Array(Set(directories.map(\.standardizedFileURL)))
      .sorted { $0.path.count < $1.path.count }
    var result: [URL] = []
    for directory in unique {
      if result.contains(where: { directory.isContained(in: $0) }) {
        continue
      }
      result.append(directory.isContained(in: libraryRoot) ? directory : libraryRoot)
    }
    return result.sorted { $0.path < $1.path }
  }
}

extension URL {
  fileprivate func isContained(in rootURL: URL) -> Bool {
    let candidatePath = standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path
    return candidatePath == rootPath
      || candidatePath.hasPrefix(rootPath + "/")
  }
}
