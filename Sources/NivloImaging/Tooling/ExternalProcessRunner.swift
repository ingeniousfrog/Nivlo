import Foundation

public struct ProcessResult: Sendable, Equatable {
  public let exitCode: Int32
  public let stdout: String
  public let stderr: String

  public init(exitCode: Int32, stdout: String, stderr: String) {
    self.exitCode = exitCode
    self.stdout = stdout
    self.stderr = stderr
  }
}

public enum ExternalProcessError: Error, LocalizedError, Equatable, Sendable {
  case executableNotFound(URL)
  case launchFailed(URL, String)
  case nonZeroExit(ProcessResult)
  case timedOut

  public var errorDescription: String? {
    switch self {
    case .executableNotFound(let url):
      "Executable not found at \(url.path)."
    case .launchFailed(let url, let message):
      "Could not launch \(url.lastPathComponent): \(message)"
    case .nonZeroExit(let result):
      result.stderr.isEmpty
        ? "Process exited with code \(result.exitCode)."
        : result.stderr
    case .timedOut:
      "Process timed out."
    }
  }
}

public struct ExternalProcessRequest: Sendable {
  public let executable: URL
  public let arguments: [String]
  public let environment: [String: String]?
  public let timeoutSeconds: TimeInterval?

  public init(
    executable: URL,
    arguments: [String] = [],
    environment: [String: String]? = nil,
    timeoutSeconds: TimeInterval? = 300
  ) {
    self.executable = executable
    self.arguments = arguments
    self.environment = environment
    self.timeoutSeconds = timeoutSeconds
  }
}

public struct ExternalProcessRunner: Sendable {
  public init() {}

  public func run(_ request: ExternalProcessRequest) async throws -> ProcessResult {
    try await Task.detached(priority: .utility) {
      try Self.runSynchronously(request)
    }.value
  }

  private static func runSynchronously(_ request: ExternalProcessRequest) throws -> ProcessResult {
    guard FileManager.default.isExecutableFile(atPath: request.executable.path) else {
      throw ExternalProcessError.executableNotFound(request.executable)
    }

    let process = Process()
    process.executableURL = request.executable
    process.arguments = request.arguments
    if let environment = request.environment {
      process.environment = environment
    }

    let stdoutPipe = Pipe()
    let stderrPipe = Pipe()
    process.standardOutput = stdoutPipe
    process.standardError = stderrPipe

    do {
      try process.run()
    } catch {
      throw ExternalProcessError.launchFailed(request.executable, error.localizedDescription)
    }

    if let timeout = request.timeoutSeconds {
      let deadline = Date().addingTimeInterval(timeout)
      while process.isRunning, Date() < deadline {
        Thread.sleep(forTimeInterval: 0.05)
      }
      if process.isRunning {
        process.terminate()
        throw ExternalProcessError.timedOut
      }
    } else {
      process.waitUntilExit()
    }

    let stdout = String(
      data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    let stderr = String(
      data: stderrPipe.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    let result = ProcessResult(
      exitCode: process.terminationStatus,
      stdout: stdout,
      stderr: stderr
    )
    guard result.exitCode == 0 else {
      throw ExternalProcessError.nonZeroExit(result)
    }
    return result
  }
}
