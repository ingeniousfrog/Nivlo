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
  @State private var currentSeconds = 0.0
  @State private var normalizedCrop = NormalizedCropRect.full
  @State private var scaleWidth = ""
  @State private var scaleHeight = ""
  @State private var transposeQuarterTurns = 0
  @State private var outputFPS = ""
  @State private var crf = 23.0
  @State private var outputFormat: VideoOutputFormat = .mp4
  @State private var extractAudioOnly = false
  @State private var audioFormat: VideoAudioExportFormat = .m4a
  @State private var volume = 1.0
  @State private var fadeInSeconds = 0.0
  @State private var fadeOutSeconds = 0.0
  @State private var selectedPresetID = "h264-balanced"
  @State private var useHardwareEncoding = true
  @State private var capabilities = FFmpegCapabilities(videoEncoders: [])
  @State private var timelineThumbnails: [VideoTimelineThumbnail] = []
  @State private var waveform: [Double] = []
  @State private var timeObserverToken: Any?
  @State private var sessionSaveTask: Task<Void, Never>?
  @State private var exportProgress: Double?
  @State private var isLoading = true
  @State private var isExporting = false
  @State private var message: String?
  @State private var lastExportedURL: URL?

  private let ffprobe = FFprobeService()
  private let ffmpeg = FFmpegProcessor()
  private let timelineAnalyzer = VideoTimelineAnalyzer()
  private let capabilityDetector = FFmpegCapabilityDetector()
  private let sessionStore = EditSessionStoreProvider.shared
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
      removeTimeObserver()
      player?.pause()
      player = nil
      sessionSaveTask?.cancel()
      saveVideoSessionImmediately()
    }
    .onChange(of: videoSession) { _, session in
      scheduleSessionSave(session)
    }
    .onChange(of: volume) { _, value in
      player?.volume = Float(value)
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
      Button {
        dismiss()
      } label: {
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
    VStack(spacing: 10) {
      ZStack {
        Color.black
        if let player {
          GeometryReader { proxy in
            ZStack {
              VideoPlayer(player: player)
                .padding(16)
              if selectedTab == .transform, let probeInfo {
                let layout = EditorImageLayout(
                  imageSize: CGSize(
                    width: max(probeInfo.width, 1),
                    height: max(probeInfo.height, 1)
                  ),
                  containerSize: CGSize(
                    width: max(0, proxy.size.width - 32),
                    height: max(0, proxy.size.height - 32)
                  )
                )
                InteractiveCropOverlay(cropRect: $normalizedCrop)
                  .frame(
                    width: layout.contentRect.width,
                    height: layout.contentRect.height
                  )
                  .position(
                    x: proxy.size.width / 2,
                    y: proxy.size.height / 2
                  )
              }
            }
          }
        } else if isLoading {
          ProgressView().controlSize(.large)
        } else {
          ContentUnavailableView(language.videoPreviewUnavailable, systemImage: "film.stack")
        }
      }
      VideoTimelineView(
        thumbnails: timelineThumbnails,
        waveform: waveform,
        durationSeconds: durationSeconds,
        currentSeconds: currentSeconds,
        startSeconds: startSeconds,
        endSeconds: endSeconds,
        onSeek: seek
      )
      .padding(.horizontal, 16)
      .padding(.bottom, 12)
    }
    .background(Color.black)
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
      HStack {
        Text("\(language.playhead): \(formatTime(currentSeconds))")
          .font(.caption.monospacedDigit())
        Spacer()
        Button {
          stepFrame(-1)
        } label: {
          Image(systemName: "backward.frame")
        }
        .help(language.previousFrame)
        Button {
          stepFrame(1)
        } label: {
          Image(systemName: "forward.frame")
        }
        .help(language.nextFrame)
      }
      sliderRow(language.trimStart, value: $startSeconds, range: 0...max(0.1, endSeconds - 0.1))
      sliderRow(
        language.trimEnd,
        value: $endSeconds,
        range: min(durationSeconds, startSeconds + 0.1)...max(durationSeconds, startSeconds + 0.1)
      )
      HStack {
        Button(language.setTrimStart) {
          startSeconds = min(currentSeconds, endSeconds - 0.1)
        }
        Button(language.setTrimEnd) {
          endSeconds = max(currentSeconds, startSeconds + 0.1)
        }
      }
    }
  }

  private var transformControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      if let probe = probeInfo {
        Text(
          "\(language.dimensions): \(probe.width)×\(probe.height) · \(String(format: "%.2f", probe.frameRate)) fps"
        )
        .font(.caption)
        .foregroundStyle(.secondary)
      }
      Group {
        Text(
          "\(language.cropSizeLabel): \(Int(normalizedCrop.width * 100))% × \(Int(normalizedCrop.height * 100))%"
        )
        .font(.caption.monospacedDigit())
        Button(language.resetCrop) {
          normalizedCrop = .full
        }
        TextField(language.scaleWidth, text: $scaleWidth)
        TextField(language.scaleHeight, text: $scaleHeight)
        TextField(language.outputFPS, text: $outputFPS)
      }
      Stepper(
        "\(language.rotateVideo): \(transposeQuarterTurns)", value: $transposeQuarterTurns,
        in: 0...3)
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
        Picker(language.videoPreset, selection: $selectedPresetID) {
          ForEach(VideoExportPreset.builtIn) { preset in
            Text(preset.name).tag(preset.id)
          }
        }
        .onChange(of: selectedPresetID) { _, _ in
          applySelectedPreset()
        }
        Toggle(language.hardwareEncoding, isOn: $useHardwareEncoding)
          .disabled(selectedPreset?.hardwareCodec == nil)
        if let selectedPreset {
          Text(
            "\(language.detectedCodec): \(selectedCodec(for: selectedPreset))"
          )
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
        }
        Picker(language.exportFormat, selection: $outputFormat) {
          ForEach(VideoOutputFormat.allCases, id: \.self) { format in
            Text(format.rawValue.uppercased()).tag(format)
          }
        }
        Slider(value: $crf, in: 18...35, step: 1) {
          Text("\(language.videoCRF): \(Int(crf))")
        }
      }

      Divider()
      sliderRow(
        language.volume,
        value: $volume,
        range: 0...2,
        formatsAsTime: false
      )
      sliderRow(
        language.fadeIn,
        value: $fadeInSeconds,
        range: 0...max(0.1, min(10, trimRange.endSeconds - trimRange.startSeconds)),
        formatsAsTime: true
      )
      sliderRow(
        language.fadeOut,
        value: $fadeOutSeconds,
        range: 0...max(0.1, min(10, trimRange.endSeconds - trimRange.startSeconds)),
        formatsAsTime: true
      )

      Button {
        exportEditedCopy()
      } label: {
        Label(exportActionTitle, systemImage: extractAudioOnly ? "waveform" : "film")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isLoading || isExporting || durationSeconds <= 0 || !toolsReady)
    }
  }

  private func sliderRow(_ title: String, value: Binding<Double>, range: ClosedRange<Double>)
    -> some View
  {
    sliderRow(title, value: value, range: range, formatsAsTime: true)
  }

  private func sliderRow(
    _ title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>,
    formatsAsTime: Bool
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(title)
          .font(.caption)
        Spacer()
        Text(
          formatsAsTime
            ? formatTime(value.wrappedValue)
            : value.wrappedValue.formatted(.number.precision(.fractionLength(2)))
        )
        .monospacedDigit()
        .font(.caption)
      }
      Slider(
        value: Binding(
          get: { value.wrappedValue },
          set: { newValue in
            value.wrappedValue = newValue
            if formatsAsTime {
              seek(newValue)
            }
          }
        ),
        in: range
      )
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
        scaleWidth = probe.width > 0 ? String(probe.width) : ""
        scaleHeight = probe.height > 0 ? String(probe.height) : ""
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
      player?.volume = Float(volume)
      installTimeObserver()
      await restoreVideoSession()
      async let thumbnails = timelineAnalyzer.thumbnails(
        sourceURL: asset.url,
        count: 12
      )
      async let audioWaveform = timelineAnalyzer.waveformAsync(
        sourceURL: asset.url,
        sampleCount: 256
      )
      timelineThumbnails = (try? await thumbnails) ?? []
      waveform = (try? await audioWaveform) ?? []
      capabilities =
        (try? await capabilityDetector.detect())
        ?? FFmpegCapabilities(videoEncoders: [])
      applySelectedPreset()
    } catch {
      message = "\(language.videoPreviewUnavailable): \(error.localizedDescription)"
    }
    isLoading = false
  }

  private func seek(_ seconds: Double) {
    let target = min(max(seconds, 0), durationSeconds)
    currentSeconds = target
    player?.seek(
      to: CMTime(seconds: target, preferredTimescale: 600),
      toleranceBefore: .zero,
      toleranceAfter: .zero
    )
  }

  private func exportEditedCopy() {
    let panel = NSSavePanel()
    panel.title = exportActionTitle
    let suffix = extractAudioOnly ? audioFormat.rawValue : outputFormat.rawValue
    panel.nameFieldStringValue =
      "\(asset.url.deletingPathExtension().lastPathComponent)-\(extractAudioOnly ? "audio" : "edited").\(suffix)"
    panel.allowedContentTypes =
      extractAudioOnly
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
    if !normalizedCrop.isEffectivelyFull,
      let probeInfo,
      probeInfo.width > 0,
      probeInfo.height > 0
    {
      cropRect = VideoCropRect(
        normalized: normalizedCrop,
        sourceWidth: probeInfo.width,
        sourceHeight: probeInfo.height
      )
    } else {
      cropRect = nil
    }
    let preset = selectedPreset ?? VideoExportPreset.builtIn[0]
    return VideoEditRequest(
      sourceURL: asset.url,
      outputURL: outputURL,
      trimRange: trimRange,
      cropRect: cropRect,
      scaleWidth: Int(scaleWidth),
      scaleHeight: Int(scaleHeight),
      transposeQuarterTurns: transposeQuarterTurns,
      outputFPS: Double(outputFPS),
      videoCodec: selectedCodec(for: preset),
      crf: Int(crf),
      preset: preset.encoderPreset,
      outputFormat: outputFormat,
      extractAudioOnly: extractAudioOnly,
      audioFormat: audioFormat,
      volume: volume,
      fadeInSeconds: fadeInSeconds,
      fadeOutSeconds: fadeOutSeconds
    )
  }

  private func formatTime(_ seconds: Double) -> String {
    let totalSeconds = max(0, Int(seconds.rounded()))
    return String(format: "%02d:%02d", totalSeconds / 60, totalSeconds % 60)
  }

  private var selectedPreset: VideoExportPreset? {
    VideoExportPreset.builtIn.first { $0.id == selectedPresetID }
  }

  private func selectedCodec(for preset: VideoExportPreset) -> String {
    useHardwareEncoding
      ? capabilities.codec(for: preset)
      : preset.softwareCodec
  }

  private func applySelectedPreset() {
    guard let preset = selectedPreset else { return }
    outputFormat = preset.outputFormat
    crf = Double(preset.crf)
  }

  private func stepFrame(_ direction: Int) {
    let frameRate = max(probeInfo?.frameRate ?? 30, 1)
    seek(currentSeconds + Double(direction) / frameRate)
  }

  private func installTimeObserver() {
    removeTimeObserver()
    timeObserverToken = player?.addPeriodicTimeObserver(
      forInterval: CMTime(value: 1, timescale: 30),
      queue: .main
    ) { time in
      let seconds = time.seconds
      Task { @MainActor in
        currentSeconds = min(max(seconds, 0), durationSeconds)
      }
    }
  }

  private func removeTimeObserver() {
    if let timeObserverToken {
      player?.removeTimeObserver(timeObserverToken)
      self.timeObserverToken = nil
    }
  }

  private var videoSession: VideoEditSession {
    VideoEditSession(
      sourceURL: asset.url,
      durationSeconds: durationSeconds,
      startSeconds: startSeconds,
      endSeconds: endSeconds,
      normalizedCrop: normalizedCrop,
      scaleWidth: Int(scaleWidth),
      scaleHeight: Int(scaleHeight),
      transposeQuarterTurns: transposeQuarterTurns,
      outputFPS: Double(outputFPS),
      volume: volume,
      fadeInSeconds: fadeInSeconds,
      fadeOutSeconds: fadeOutSeconds,
      exportPresetID: selectedPresetID,
      outputFormat: outputFormat,
      extractAudioOnly: extractAudioOnly,
      audioFormat: audioFormat
    )
  }

  private func restoreVideoSession() async {
    guard
      let sessionStore,
      let session = try? await sessionStore.videoSession(for: asset.id),
      session.sourceURL.standardizedFileURL == asset.url.standardizedFileURL
    else {
      return
    }
    startSeconds = session.startSeconds
    endSeconds = session.endSeconds
    normalizedCrop = session.normalizedCrop
    scaleWidth = session.scaleWidth.map(String.init) ?? scaleWidth
    scaleHeight = session.scaleHeight.map(String.init) ?? scaleHeight
    transposeQuarterTurns = session.transposeQuarterTurns
    outputFPS = session.outputFPS.map { String(format: "%.2f", $0) } ?? outputFPS
    volume = session.volume
    fadeInSeconds = session.fadeInSeconds
    fadeOutSeconds = session.fadeOutSeconds
    selectedPresetID = session.exportPresetID
    outputFormat = session.outputFormat
    extractAudioOnly = session.extractAudioOnly
    audioFormat = session.audioFormat
  }

  private func scheduleSessionSave(_ session: VideoEditSession) {
    guard durationSeconds > 0, let sessionStore else { return }
    sessionSaveTask?.cancel()
    sessionSaveTask = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      try? await sessionStore.saveVideoSession(session, for: asset.id)
    }
  }

  private func saveVideoSessionImmediately() {
    guard durationSeconds > 0, let sessionStore else { return }
    let session = videoSession
    Task {
      try? await sessionStore.saveVideoSession(session, for: asset.id)
    }
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
