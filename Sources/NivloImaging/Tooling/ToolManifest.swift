import Foundation

public enum ToolBootstrapPhase: String, Codable, Sendable, Equatable {
  case idle
  case checking
  case installingFFmpeg
  case installingPicx
  case ready
  case failed
}

public struct ToolManifest: Codable, Sendable, Equatable {
  public var ffmpegURL: URL?
  public var ffprobeURL: URL?
  public var picxURL: URL?
  public var pythonURL: URL?
  public var phase: ToolBootstrapPhase
  public var lastError: String?
  public var updatedAt: Date

  public init(
    ffmpegURL: URL? = nil,
    ffprobeURL: URL? = nil,
    picxURL: URL? = nil,
    pythonURL: URL? = nil,
    phase: ToolBootstrapPhase = .idle,
    lastError: String? = nil,
    updatedAt: Date = Date()
  ) {
    self.ffmpegURL = ffmpegURL
    self.ffprobeURL = ffprobeURL
    self.picxURL = picxURL
    self.pythonURL = pythonURL
    self.phase = phase
    self.lastError = lastError
    self.updatedAt = updatedAt
  }

  public var isReady: Bool {
    ffmpegURL != nil && ffprobeURL != nil && picxURL != nil && phase == .ready
  }
}

public enum NivloToolsDirectory {
  public static func root() -> URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first ?? FileManager.default.temporaryDirectory
    return base.appending(path: "Nivlo/tools", directoryHint: .isDirectory)
  }

  public static func binDirectory() -> URL {
    root().appending(path: "bin", directoryHint: .isDirectory)
  }

  public static func venvDirectory() -> URL {
    root().appending(path: "venv", directoryHint: .isDirectory)
  }

  public static func manifestURL() -> URL {
    root().appending(path: "manifest.json")
  }

  public static func tempDirectory() -> URL {
    root().appending(path: "tmp", directoryHint: .isDirectory)
  }
}
