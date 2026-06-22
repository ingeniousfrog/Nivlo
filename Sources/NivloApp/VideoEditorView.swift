import AVFoundation
import AVKit
import AppKit
import NivloDomain
import SwiftUI
import UniformTypeIdentifiers

struct VideoEditorView: View {
  let asset: ImageAsset
  let language: NivloLanguage

  @Environment(\.dismiss) private var dismiss
  @State private var player: AVPlayer?
  @State private var durationSeconds = 0.0
  @State private var startSeconds = 0.0
  @State private var endSeconds = 0.0
  @State private var isLoading = true
  @State private var isExporting = false
  @State private var message: String?

  private var trimRange: VideoTrimRange {
    VideoTrimRange(
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      durationSeconds: durationSeconds,
      minimumDurationSeconds: 0.1
    )
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      ZStack {
        Color.black
        if let player {
          VideoPlayer(player: player)
        } else if isLoading {
          ProgressView()
            .controlSize(.large)
        } else {
          ContentUnavailableView(
            language.videoPreviewUnavailable,
            systemImage: "film.stack"
          )
        }
      }
      .frame(minHeight: 480)

      trimControls
        .padding(18)
        .background(.bar)
    }
    .frame(minWidth: 960, minHeight: 720)
    .task(id: asset.url.standardizedFileURL.path) {
      await loadVideo()
    }
    .onDisappear {
      player?.pause()
      player = nil
    }
  }

  private var toolbar: some View {
    HStack(spacing: 10) {
      VStack(alignment: .leading, spacing: 2) {
        Text(language.videoEditorTitle)
          .font(.headline)
        Text(asset.filename)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Spacer()
      Button {
        exportTrimmedCopy()
      } label: {
        Label(language.exportTrimmedVideo, systemImage: "square.and.arrow.up")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isLoading || isExporting || durationSeconds <= 0)
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.bordered)
      .keyboardShortcut(.cancelAction)
      .help(language.close)
    }
    .padding(16)
  }

  private var trimControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack {
        Text(language.trimVideo)
          .font(.headline)
        Spacer()
        Text(
          "\(formatTime(trimRange.startSeconds)) – \(formatTime(trimRange.endSeconds))"
        )
        .monospacedDigit()
        .foregroundStyle(.secondary)
      }

      HStack(spacing: 12) {
        Text(language.trimStart)
          .frame(width: 52, alignment: .leading)
        Slider(
          value: $startSeconds,
          in: 0...max(0.1, endSeconds - 0.1),
          onEditingChanged: seekWhenFinished
        )
        Text(formatTime(startSeconds))
          .monospacedDigit()
          .frame(width: 64, alignment: .trailing)
      }

      HStack(spacing: 12) {
        Text(language.trimEnd)
          .frame(width: 52, alignment: .leading)
        Slider(
          value: $endSeconds,
          in: min(
            durationSeconds, startSeconds + 0.1)...max(
              min(durationSeconds, startSeconds + 0.1),
              durationSeconds
            ),
          onEditingChanged: seekWhenFinished
        )
        Text(formatTime(endSeconds))
          .monospacedDigit()
          .frame(width: 64, alignment: .trailing)
      }

      if let message {
        Text(message)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
  }

  private func loadVideo() async {
    isLoading = true
    message = nil
    let avAsset = AVURLAsset(url: asset.url)
    do {
      let duration = try await avAsset.load(.duration)
      let seconds = duration.seconds
      guard seconds.isFinite, seconds > 0 else {
        throw VideoEditorError.invalidDuration
      }
      durationSeconds = seconds
      startSeconds = 0
      endSeconds = seconds
      player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
    } catch {
      message = "\(language.videoPreviewUnavailable): \(error.localizedDescription)"
    }
    isLoading = false
  }

  private func seekWhenFinished(_ isEditing: Bool) {
    guard !isEditing else {
      return
    }
    let target = min(max(startSeconds, 0), durationSeconds)
    player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
  }

  private func exportTrimmedCopy() {
    let panel = NSSavePanel()
    panel.title = language.exportTrimmedVideo
    panel.nameFieldStringValue =
      "\(asset.url.deletingPathExtension().lastPathComponent)-trimmed.mp4"
    panel.allowedContentTypes = [.mpeg4Movie]
    guard panel.runModal() == .OK, let outputURL = panel.url else {
      return
    }
    guard outputURL.standardizedFileURL != asset.url.standardizedFileURL else {
      message = language.originalFileProtected
      return
    }

    let range = trimRange
    isExporting = true
    message = language.exportingVideo
    Task {
      do {
        try await VideoTrimExporter.export(
          sourceURL: asset.url,
          outputURL: outputURL,
          range: range
        )
        message = language.videoExported
      } catch {
        message = "\(language.videoExportFailed): \(error.localizedDescription)"
      }
      isExporting = false
    }
  }

  private func formatTime(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    return String(
      format: "%02d:%02d",
      totalSeconds / 60,
      totalSeconds % 60
    )
  }
}

private enum VideoTrimExporter {
  static func export(
    sourceURL: URL,
    outputURL: URL,
    range: VideoTrimRange
  ) async throws {
    let asset = AVURLAsset(url: sourceURL)
    guard
      let exporter = AVAssetExportSession(
        asset: asset,
        presetName: AVAssetExportPresetHighestQuality
      )
    else {
      throw VideoEditorError.exportSessionUnavailable
    }
    if FileManager.default.fileExists(atPath: outputURL.path) {
      try FileManager.default.removeItem(at: outputURL)
    }
    exporter.outputURL = outputURL
    exporter.outputFileType = .mp4
    exporter.shouldOptimizeForNetworkUse = true
    exporter.timeRange = CMTimeRange(
      start: CMTime(seconds: range.startSeconds, preferredTimescale: 600),
      end: CMTime(seconds: range.endSeconds, preferredTimescale: 600)
    )

    await exporter.export()
    switch exporter.status {
    case .completed:
      return
    case .cancelled:
      throw CancellationError()
    default:
      throw exporter.error ?? VideoEditorError.exportFailed
    }
  }
}

private enum VideoEditorError: Error, LocalizedError {
  case invalidDuration
  case exportSessionUnavailable
  case exportFailed

  var errorDescription: String? {
    switch self {
    case .invalidDuration:
      "The video duration is unavailable."
    case .exportSessionUnavailable:
      "This video cannot be exported with the available codecs."
    case .exportFailed:
      "The trimmed video could not be exported."
    }
  }
}
