import Foundation

public enum ToolBootstrapperError: Error, LocalizedError, Sendable {
  case downloadFailed(String)
  case installFailed(String)
  case pythonUnavailable

  public var errorDescription: String? {
    switch self {
    case .downloadFailed(let detail):
      "Tool download failed: \(detail)"
    case .installFailed(let detail):
      "Tool install failed: \(detail)"
    case .pythonUnavailable:
      "Python 3 is required to install picx but was not found."
    }
  }
}

@MainActor
public final class ToolBootstrapper: ObservableObject {
  public static let shared = ToolBootstrapper()

  @Published public private(set) var manifest = ToolManifest()
  @Published public private(set) var statusMessage = "Tools idle"

  private let runner = ExternalProcessRunner()
  private let fileManager = FileManager.default
  private var bootstrapTask: Task<Void, Never>?

  private init() {
    manifest = (try? loadManifest()) ?? ToolManifest()
  }

  public var isReady: Bool {
    manifest.isReady
  }

  public func ensureToolsReady() {
    guard bootstrapTask == nil else {
      return
    }
    bootstrapTask = Task { [weak self] in
      await self?.bootstrap()
      self?.bootstrapTask = nil
    }
  }

  public func retry() {
    bootstrapTask?.cancel()
    bootstrapTask = nil
    manifest.phase = .idle
    ensureToolsReady()
  }

  private func bootstrap() async {
    manifest.phase = .checking
    statusMessage = "Checking image and video tools…"
    persistManifest()

    do {
      let ffmpeg = try await resolveFFmpeg()
      let ffprobe = try await resolveFFprobe()
      manifest.ffmpegURL = ffmpeg
      manifest.ffprobeURL = ffprobe

      manifest.phase = .installingPicx
      statusMessage = "Preparing picx…"
      persistManifest()

      let picx = try await resolvePicx()
      manifest.picxURL = picx
      manifest.phase = .ready
      manifest.lastError = nil
      statusMessage = "Image and video tools ready"
    } catch {
      manifest.phase = .failed
      manifest.lastError = error.localizedDescription
      statusMessage = "Tool setup failed"
    }
    persistManifest()
  }

  private func resolveFFmpeg() async throws -> URL {
    manifest.phase = .installingFFmpeg
    statusMessage = "Preparing ffmpeg…"
    persistManifest()

    if let existing = discoverExecutable(named: "ffmpeg") {
      return existing
    }
    let managed = NivloToolsDirectory.binDirectory().appending(path: "ffmpeg")
    if fileManager.isExecutableFile(atPath: managed.path) {
      return managed
    }
    try await installEvermeetBinary(name: "ffmpeg", destination: managed)
    return managed
  }

  private func resolveFFprobe() async throws -> URL {
    if let existing = discoverExecutable(named: "ffprobe") {
      return existing
    }
    let managed = NivloToolsDirectory.binDirectory().appending(path: "ffprobe")
    if fileManager.isExecutableFile(atPath: managed.path) {
      return managed
    }
    try await installEvermeetBinary(name: "ffprobe", destination: managed)
    return managed
  }

  private func resolvePicx() async throws -> URL {
    let venvPicx = NivloToolsDirectory.venvDirectory()
      .appending(path: "bin/picx")
    if fileManager.isExecutableFile(atPath: venvPicx.path) {
      manifest.pythonURL = NivloToolsDirectory.venvDirectory().appending(path: "bin/python3")
      return venvPicx
    }

    let python = try resolvePython()
    manifest.pythonURL = python
    try fileManager.createDirectory(
      at: NivloToolsDirectory.venvDirectory(),
      withIntermediateDirectories: true
    )

    _ = try await runner.run(
      ExternalProcessRequest(
        executable: python,
        arguments: ["-m", "venv", NivloToolsDirectory.venvDirectory().path]
      )
    )

    let venvPython = NivloToolsDirectory.venvDirectory().appending(path: "bin/python3")
    _ = try await runner.run(
      ExternalProcessRequest(
        executable: venvPython,
        arguments: [
          "-m", "pip", "install", "--upgrade", "pip", "picx-image-optimizer",
        ],
        timeoutSeconds: 600
      )
    )

    guard fileManager.isExecutableFile(atPath: venvPicx.path) else {
      throw ToolBootstrapperError.installFailed("picx CLI was not created in the venv.")
    }
    return venvPicx
  }

  private func resolvePython() throws -> URL {
    let candidates = [
      "/opt/homebrew/bin/python3",
      "/usr/local/bin/python3",
      "/usr/bin/python3",
    ].map { URL(fileURLWithPath: $0) }
    for candidate in candidates where fileManager.isExecutableFile(atPath: candidate.path) {
      return candidate
    }
    if let path = discoverExecutable(named: "python3") {
      return path
    }
    throw ToolBootstrapperError.pythonUnavailable
  }

  private func discoverExecutable(named name: String) -> URL? {
    let paths = ProcessInfo.processInfo.environment["PATH"]?
      .split(separator: ":")
      .map(String.init) ?? []
    for directory in paths {
      let candidate = URL(filePath: directory).appending(path: name)
      if fileManager.isExecutableFile(atPath: candidate.path) {
        return candidate
      }
    }
    return nil
  }

  private func installEvermeetBinary(name: String, destination: URL) async throws {
    try fileManager.createDirectory(
      at: NivloToolsDirectory.binDirectory(),
      withIntermediateDirectories: true
    )
    let zipURL = NivloToolsDirectory.root().appending(path: "\(name).zip")
    let downloadURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/\(name)/zip")!
    do {
      let (tempURL, _) = try await URLSession.shared.download(from: downloadURL)
      if fileManager.fileExists(atPath: zipURL.path) {
        try fileManager.removeItem(at: zipURL)
      }
      try fileManager.moveItem(at: tempURL, to: zipURL)
    } catch {
      throw ToolBootstrapperError.downloadFailed(error.localizedDescription)
    }

    let unzip = URL(fileURLWithPath: "/usr/bin/unzip")
    guard fileManager.isExecutableFile(atPath: unzip.path) else {
      throw ToolBootstrapperError.installFailed("unzip is unavailable.")
    }
    _ = try await runner.run(
      ExternalProcessRequest(
        executable: unzip,
        arguments: ["-o", zipURL.path, "-d", NivloToolsDirectory.binDirectory().path]
      )
    )
    try? fileManager.removeItem(at: zipURL)

    let extracted = NivloToolsDirectory.binDirectory().appending(path: name)
    guard fileManager.fileExists(atPath: extracted.path) else {
      throw ToolBootstrapperError.installFailed("\(name) was not extracted.")
    }
    try fileManager.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: extracted.path
    )
    if extracted != destination, fileManager.fileExists(atPath: destination.path) {
      try fileManager.removeItem(at: destination)
    }
    if extracted != destination {
      try fileManager.moveItem(at: extracted, to: destination)
    }
  }

  private func loadManifest() throws -> ToolManifest {
    let url = NivloToolsDirectory.manifestURL()
    guard fileManager.fileExists(atPath: url.path) else {
      return ToolManifest()
    }
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(ToolManifest.self, from: data)
  }

  private func persistManifest() {
    manifest.updatedAt = Date()
    do {
      try fileManager.createDirectory(
        at: NivloToolsDirectory.root(),
        withIntermediateDirectories: true
      )
      let data = try JSONEncoder().encode(manifest)
      try data.write(to: NivloToolsDirectory.manifestURL(), options: .atomic)
    } catch {
      // Best-effort persistence.
    }
  }
}
