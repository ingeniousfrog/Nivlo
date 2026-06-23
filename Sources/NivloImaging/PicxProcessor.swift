import Foundation
import NivloDomain

public enum PicxProcessorError: Error, LocalizedError, Sendable {
  case picxUnavailable
  case outputMissing

  public var errorDescription: String? {
    switch self {
    case .picxUnavailable:
      "picx is not installed yet."
    case .outputMissing:
      "picx did not produce an output file."
    }
  }
}

public protocol ImageOptimizing: Sendable {
  func optimize(_ request: PicxOptimizeRequest) async throws -> PicxOptimizeResult
}

public struct PicxProcessor: Sendable, ImageOptimizing {
  private let runner: ExternalProcessRunner
  private let picxExecutable: URL?

  public init(picxExecutable: URL? = nil, runner: ExternalProcessRunner = ExternalProcessRunner()) {
    self.picxExecutable = picxExecutable
    self.runner = runner
  }

  public func optimize(_ request: PicxOptimizeRequest) async throws -> PicxOptimizeResult {
    let picx: URL?
    if let picxExecutable {
      picx = picxExecutable
    } else {
      picx = await MainActor.run { ToolBootstrapper.shared.manifest.picxURL }
    }
    guard let picx else {
      throw PicxProcessorError.picxUnavailable
    }

    var arguments = [
      "image",
      request.sourceURL.path,
      "--output",
      request.outputURL.path,
      "--format",
      request.format.cliValue,
      "--quality",
      String(request.quality),
    ]
    if let preset = request.preset {
      arguments.append(contentsOf: ["--preset", preset.rawValue])
    }
    if let maxWidth = request.maxWidth {
      arguments.append(contentsOf: ["--max-width", String(maxWidth)])
    }
    if let maxHeight = request.maxHeight {
      arguments.append(contentsOf: ["--max-height", String(maxHeight)])
    }
    if let targetSize = request.targetSizeBytes {
      arguments.append(contentsOf: ["--target-size", String(targetSize)])
    }

    let originalSize = fileSize(at: request.sourceURL)
    _ = try await runner.run(
      ExternalProcessRequest(executable: picx, arguments: arguments)
    )

    guard FileManager.default.fileExists(atPath: request.outputURL.path) else {
      throw PicxProcessorError.outputMissing
    }
    let outputSize = fileSize(at: request.outputURL)
    let savings =
      originalSize > 0
      ? Double(originalSize - outputSize) / Double(originalSize)
      : 0
    return PicxOptimizeResult(
      sourceURL: request.sourceURL,
      outputURL: request.outputURL,
      originalSize: originalSize,
      outputSize: outputSize,
      savingsRatio: savings
    )
  }

  private func fileSize(at url: URL) -> Int64 {
    (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?
      .int64Value ?? 0
  }
}

public struct ImageEditPipeline: Sendable {
  private let renderer: any EditedImageRendering
  private let optimizer: any ImageOptimizing

  public init(
    renderer: any EditedImageRendering = CoreImageGeometryExporter(),
    optimizer: any ImageOptimizing = PicxProcessor()
  ) {
    self.renderer = renderer
    self.optimizer = optimizer
  }

  public init(
    geometryExporter: CoreImageGeometryExporter,
    picxProcessor: PicxProcessor
  ) {
    renderer = geometryExporter
    optimizer = picxProcessor
  }

  public func export(_ request: ImageEditRequest) async throws -> PicxOptimizeResult {
    let fileManager = FileManager.default
    try fileManager.createDirectory(
      at: NivloToolsDirectory.tempDirectory(),
      withIntermediateDirectories: true
    )
    let tempPNG = NivloToolsDirectory.tempDirectory()
      .appending(path: "\(UUID().uuidString).png")
    defer { try? fileManager.removeItem(at: tempPNG) }

    try renderer.render(
      sourceURL: request.sourceURL,
      outputURL: tempPNG,
      snapshot: ImageEditSnapshot(
        cropRect: request.cropRect,
        quarterTurns: request.quarterTurns,
        flippedHorizontally: request.flippedHorizontally,
        adjustments: request.adjustments,
        annotations: request.annotations,
        maskStrokes: request.maskStrokes,
        localAdjustments: request.localAdjustments,
        layers: request.layers
      )
    )

    return try await optimizer.optimize(
      PicxOptimizeRequest(
        sourceURL: tempPNG,
        outputURL: request.outputURL,
        format: request.format,
        quality: request.quality,
        preset: request.preset,
        maxWidth: request.maxWidth,
        maxHeight: request.maxHeight,
        targetSizeBytes: request.targetSizeBytes
      )
    )
  }
}
