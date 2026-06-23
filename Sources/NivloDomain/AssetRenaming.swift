import Foundation

public struct AssetRenamePlan: Equatable, Sendable {
  public let sourceURL: URL
  public let destinationURL: URL
  public let filename: String

  public init(
    sourceURL: URL,
    destinationURL: URL,
    filename: String
  ) {
    self.sourceURL = sourceURL
    self.destinationURL = destinationURL
    self.filename = filename
  }
}

public enum AssetRenameError: Error, Equatable, LocalizedError, Sendable {
  case emptyFilename
  case invalidFilename(String)
  case reservedFilename(String)
  case unchangedFilename
  case changedExtension(original: String, proposed: String)
  case destinationExists(URL)

  public var errorDescription: String? {
    switch self {
    case .emptyFilename:
      "Enter a filename."
    case .invalidFilename(let filename):
      "'\(filename)' can’t be used as a filename."
    case .reservedFilename(let filename):
      "'\(filename)' is reserved by the file system."
    case .unchangedFilename:
      "Enter a different filename."
    case .changedExtension(let original, let proposed):
      "Keep the original file extension: \(original). Proposed extension: \(proposed)."
    case .destinationExists(let url):
      "A file named \(url.lastPathComponent) already exists in this folder."
    }
  }
}

public enum AssetRenamer {
  public static func plan(
    for asset: ImageAsset,
    proposedFilename: String,
    fileExists: (URL) -> Bool = { FileManager.default.fileExists(atPath: $0.path) }
  ) throws -> AssetRenamePlan {
    let filename = proposedFilename.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !filename.isEmpty else {
      throw AssetRenameError.emptyFilename
    }
    guard !filename.contains("/") && !filename.contains(":") else {
      throw AssetRenameError.invalidFilename(filename)
    }
    guard filename != "." && filename != ".." else {
      throw AssetRenameError.reservedFilename(filename)
    }
    guard filename != asset.filename else {
      throw AssetRenameError.unchangedFilename
    }

    let originalExtension = asset.url.pathExtension.lowercased()
    let proposedExtension = URL(filePath: filename).pathExtension.lowercased()
    guard originalExtension == proposedExtension else {
      throw AssetRenameError.changedExtension(
        original: originalExtension.isEmpty ? "none" : ".\(originalExtension)",
        proposed: proposedExtension.isEmpty ? "none" : ".\(proposedExtension)"
      )
    }

    let sourceURL = asset.url.standardizedFileURL
    let destinationURL =
      sourceURL
      .deletingLastPathComponent()
      .appending(path: filename)
      .standardizedFileURL
    guard sourceURL.path != destinationURL.path else {
      throw AssetRenameError.unchangedFilename
    }
    guard !fileExists(destinationURL) else {
      throw AssetRenameError.destinationExists(destinationURL)
    }

    return AssetRenamePlan(
      sourceURL: sourceURL,
      destinationURL: destinationURL,
      filename: filename
    )
  }
}
