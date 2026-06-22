import AVFoundation
import AVKit
import AppKit
import NivloDomain
import NivloImaging
import SwiftUI
import UniformTypeIdentifiers

private enum VideoEditorTab: String, CaseIterable, Identifiable {
  case trim
  case transform
  case export

  var id: String { rawValue }

  func title(language: NivloLanguage) -> String {
    switch self {
    case .trim: language.trimVideo
    case .transform: language.tabTransform
    case .export: language.tabExport
    }
  }

  var icon: String {
    switch self {
    case .trim: "scissors"
    case .transform: "aspectratio"
    case .export: "square.and.arrow.up"
    }
  }
}

struct VideoEditorView: View {
  let asset: ImageAsset
  let language: NivloLanguage
  let toolsReady: Bool
  let onExport: (URL, VideoEditRequest) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var selectedTab: VideoEditorTab = .trim
  @State private var player: AVPlayer?
  @State private var probeInfo: VideoProbeInfo?
  @State private var durationSeconds = 0.0
  @State private var startSeconds = 0.0
  @State private var endSeconds = 0.0
  @State private var cropX = ""
  @State private var cropY = ""
  @State private var cropWidth = ""
  @State private var cropHeight = ""
  @State private var scaleWidth = ""
  @State private var scaleHeight = ""
  @State private var transposeQuarterTurns = 0
  @State private var outputFPS = ""
  @State private var crf = 23.0
  @State private var outputFormat: VideoOutputFormat = .mp4
  @State private var extractAudioOnly = false
  @State private var audioFormat: VideoAudioExportFormat = .m4a
  @State private var exportProgress: Double?
  @State private var isLoading = true
  @State private var isExporting = false
  @State private var message: String?
  @State private var lastExportedURL: URL?

  private let ffprobe = FFprobeService()
  private let ffmpeg = FFmpegProcessor()
  private let sidebarWidth: CGFloat = 200
  private let inspectorWidth: CGFloat = 340

  private var trimRange: VideoTrimRange {
    VideoTrimRange(
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      durationSeconds: durationSeconds,
      minimumDurationSeconds: 0.1
    )
  }

  private var exportActionTitle: String {
    extractAudioOnly ? language.exportAudioOnly : language.exportTrimmedVideo
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      HStack(spacing: 0) {
        tabSidebar
        Divider()
        videoPreview
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider()
        inspector
          .frame(width: inspectorWidth)
      }
      statusBar
    }
    .frame(minWidth: 1_120, minHeight: 760)
    .task(id: asset.url.standardizedFileURL.path) {
      await loadVideo()
    }
    .onDisappear {
      player?.pause()
      player = nil
    }
  }

  private var toolbar: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(language.videoEditorTitle)
          .font(.headline)
        Text(asset.filename)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: 360, alignment: .leading)
      Spacer()
      if !toolsReady {
        Label(language.toolsNotReady, systemImage: "wrench.and.screwdriver")
          .font(.caption)
          .foregroundStyle(.orange)
      }
      Button {
        selectedTab = .export
        exportEditedCopy()
      } label: {
        Label(exportActionTitle, systemImage: extractAudioOnly ? "waveform" : "film")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isLoading || isExporting || durationSeconds <= 0 || !toolsReady)
      Button { dismiss() } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.bordered)
      .keyboardShortcut(.cancelAction)
      .help(language.close)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private var tabSidebar: some View {
    List(selection: $selectedTab) {
      ForEach(VideoEditorTab.allCases) { tab in
        Label(tab.title(language: language), systemImage: tab.icon)
          .tag(tab)
      }
    }
    .listStyle(.sidebar)
    .frame(width: sidebarWidth)
  }

  private var videoPreview: some View {
    ZStack {
      Color.black
      if let player {
        VideoPlayer(player: player)
          .padding(16)
      } else if isLoading {
        ProgressView().controlSize(.large)
      } else {
        ContentUnavailableView(language.videoPreviewUnavailable, systemImage: "film.stack")
      }
    }
  }

  private var inspector: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(selectedTab.title(language: language))
          .font(.title3.weight(.semibold))

        switch selectedTab {
        case .trim:
          trimControls
        case .transform:
          transformControls
        case .export:
          exportControls
        }

        if let exportProgress {
          VStack(alignment: .leading, spacing: 6) {
            Text(language.exportingVideo)
              .font(.caption)
              .foregroundStyle(.secondary)
            ProgressView(value: exportProgress)
          }
        }

        if let lastExportedURL {
          exportResultCard(url: lastExportedURL)
        }
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(20)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var statusBar: some View {
    HStack(spacing: 12) {
      if isExporting {
        ProgressView().controlSize(.small)
        Text(extractAudioOnly ? language.exportingAudio : language.exportingVideo)
      } else if let message {
        Text(message)
      } else {
        Text(extractAudioOnly ? language.audioExportHint : language.videoExportHint)
      }
      Spacer()
      if let lastExportedURL {
        Button(language.showInFinder) {
          NSWorkspace.shared.activateFileViewerSelecting([lastExportedURL])
        }
        .controlSize(.small)
      }
    }
    .font(.caption)
    .foregroundStyle(.secondary)
    .padding(.horizontal, 20)
    .padding(.vertical, 10)
    .background(.bar)
  }

  private func exportResultCard(url: URL) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(language.exportReadyTitle, systemImage: "checkmark.circle.fill")
        .foregroundStyle(.green)
        .font(.subheadline.weight(.semibold))
      Text(url.lastPathComponent)
        .font(.caption)
        .lineLimit(2)
        .truncationMode(.middle)
      HStack(spacing: 8) {
        Button(language.showInFinder) {
          NSWorkspace.shared.activateFileViewerSelecting([url])
        }
        .buttonStyle(.borderedProminent)
        Button(language.openExportedFile) {
          NSWorkspace.shared.open(url)
        }
        .buttonStyle(.bordered)
      }
    }
    .padding(12)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
  }

  private var trimControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack {
        Text(language.trimRangeLabel)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text("\(formatTime(trimRange.startSeconds)) – \(formatTime(trimRange.endSeconds))")
          .monospacedDigit()
          .font(.caption)
      }
      sliderRow(language.trimStart, value: $startSeconds, range: 0...max(0.1, endSeconds - 0.1))
      sliderRow(
        language.trimEnd,
        value: $endSeconds,
        range: min(durationSeconds, startSeconds + 0.1)...max(durationSeconds, startSeconds + 0.1)
      )
    }
  }

  private var transformControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let probe = probeInfo {
        Text("\(language.dimensions): \(probe.width)×\(probe.height) · \(String(format: "%.2f", probe.frameRate)) fps")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      Group {
        TextField(language.cropX, text: $cropX)
        TextField(language.cropY, text: $cropY)
        TextField(language.cropWidth, text: $cropWidth)
        TextField(language.cropHeight, text: $cropHeight)
        TextField(language.scaleWidth, text: $scaleWidth)
        TextField(language.scaleHeight, text: $scaleHeight)
        TextField(language.outputFPS, text: $outputFPS)
      }
      Stepper("\(language.rotateVideo): \(transposeQuarterTurns)", value: $transposeQuarterTurns, in: 0...3)
    }
  }

  private var exportControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      Toggle(language.extractAudioOnly, isOn: $extractAudioOnly)
      Text(language.audioExtractDescription)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      if extractAudioOnly {
        Picker(language.audioFormat, selection: $audioFormat) {
          ForEach(VideoAudioExportFormat.allCases, id: \.self) { format in
            Text(format.rawValue.uppercased()).tag(format)
          }
        }
      } else {
        Picker(language.exportFormat, selection: $outputFormat) {
          ForEach(VideoOutputFormat.allCases, id: \.self) { format in
            Text(format.rawValue.uppercased()).tag(format)
          }
        }
        Slider(value: $crf, in: 18...35, step: 1) {
          Text("\(language.videoCRF): \(Int(crf))")
        }
      }

      Button {
        exportEditedCopy()
      } label: {
        Label(exportActionTitle, systemImage: extractAudioOnly ? "waveform" : "film")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isLoading || isExporting || durationSeconds <= 0 || !toolsReady)
    }
  }

  private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.caption)
        Spacer()
        Text(formatTime(value.wrappedValue))
          .monospacedDigit()
          .font(.caption)
      }
      Slider(value: value, in: range, onEditingChanged: seekWhenFinished)
    }
  }

  private func loadVideo() async {
    isLoading = true
    message = nil
    let avAsset = AVURLAsset(url: asset.url)
    do {
      if let probe = try? await ffprobe.probe(sourceURL: asset.url) {
        probeInfo = probe
        durationSeconds = probe.durationSeconds
        cropWidth = probe.width > 0 ? String(probe.width) : ""
        cropHeight = probe.height > 0 ? String(probe.height) : ""
        scaleWidth = cropWidth
        scaleHeight = cropHeight
        outputFPS = probe.frameRate > 0 ? String(format: "%.2f", probe.frameRate) : ""
      } else {
        let duration = try await avAsset.load(.duration)
        durationSeconds = duration.seconds
      }
      guard durationSeconds.isFinite, durationSeconds > 0 else {
        throw VideoEditorError.invalidDuration
      }
      startSeconds = 0
      endSeconds = durationSeconds
      player = AVPlayer(playerItem: AVPlayerItem(asset: avAsset))
    } catch {
      message = "\(language.videoPreviewUnavailable): \(error.localizedDescription)"
    }
    isLoading = false
  }

  private func seekWhenFinished(_ isEditing: Bool) {
    guard !isEditing else { return }
    let target = min(max(startSeconds, 0), durationSeconds)
    player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
  }

  private func exportEditedCopy() {
    let panel = NSSavePanel()
    panel.title = exportActionTitle
    let suffix = extractAudioOnly ? audioFormat.rawValue : outputFormat.rawValue
    panel.nameFieldStringValue =
      "\(asset.url.deletingPathExtension().lastPathComponent)-\(extractAudioOnly ? "audio" : "edited").\(suffix)"
    panel.allowedContentTypes = extractAudioOnly
      ? [UTType(filenameExtension: audioFormat.rawValue) ?? .audio]
      : [UTType(filenameExtension: outputFormat.rawValue) ?? .mpeg4Movie]
    guard panel.runModal() == .OK, let outputURL = panel.url else { return }
    guard outputURL.standardizedFileURL != asset.url.standardizedFileURL else {
      message = language.originalFileProtected
      return
    }

    let request = buildRequest(outputURL: outputURL)
    isExporting = true
    exportProgress = nil
    message = extractAudioOnly ? language.exportingAudio : language.exportingVideo
    Task {
      do {
        let exportedURL = try await ffmpeg.export(request: request) { progress in
          Task { @MainActor in
            exportProgress = progress.fraction
          }
        }
        lastExportedURL = exportedURL
        message = extractAudioOnly ? language.audioExported : language.videoExported
        onExport(exportedURL, request)
      } catch {
        message = "\(language.videoExportFailed): \(error.localizedDescription)"
      }
      isExporting = false
      exportProgress = nil
    }
  }

  private func buildRequest(outputURL: URL) -> VideoEditRequest {
    let cropRect: VideoCropRect?
    if let width = Int(cropWidth), let height = Int(cropHeight), width > 0, height > 0 {
      cropRect = VideoCropRect(
        x: Int(cropX) ?? 0,
        y: Int(cropY) ?? 0,
        width: width,
        height: height
      )
    } else {
      cropRect = nil
    }
    return VideoEditRequest(
      sourceURL: asset.url,
      outputURL: outputURL,
      trimRange: trimRange,
      cropRect: cropRect,
      scaleWidth: Int(scaleWidth),
      scaleHeight: Int(scaleHeight),
      transposeQuarterTurns: transposeQuarterTurns,
      outputFPS: Double(outputFPS),
      crf: Int(crf),
      outputFormat: outputFormat,
      extractAudioOnly: extractAudioOnly,
      audioFormat: audioFormat
    )
  }

  private func formatTime(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
  }
}

private enum VideoEditorError: Error, LocalizedError {
  case invalidDuration

  var errorDescription: String? {
    switch self {
    case .invalidDuration:
      "The video duration is unavailable."
    }
  }
}
