import AppKit
import NivloDomain
import NivloImaging
import NivloPersistence
import SwiftUI
import UniformTypeIdentifiers

extension ImageEditSnapshot {
  fileprivate static let defaultInitial = ImageEditSnapshot(cropRect: .full)
}

struct AssetEditorView: View {
  let asset: ImageAsset
  let language: NivloLanguage
  let toolsReady: Bool
  let onExport: (PicxOptimizeResult, ImageEditRequest) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var selectedTool: ImageEditorTool = .geometry
  @State private var editSession = ImageEditSession(
    initialSnapshot: ImageEditSnapshot.defaultInitial
  )
  @State private var selectedAnnotationID: UUID?
  @State private var currentMaskStroke: MaskStroke?
  @State private var brushRadius = 0.035
  @State private var maskOperation: MaskStrokeOperation = .paint
  @State private var outputFormat: PicxOutputFormat = .webp
  @State private var quality = 82.0
  @State private var preset: PicxPreset = .web
  @State private var maxWidth = ""
  @State private var maxHeight = ""
  @State private var targetSizeKB = ""
  @State private var exportMessage: String?
  @State private var lastExportedURL: URL?
  @State private var isExporting = false
  @State private var isExportOptionsPresented = false
  @State private var isCropEditing = true
  @State private var histogram: ImageHistogram?
  @State private var customAdjustmentPresets: [ImageAdjustmentPreset] = []
  @State private var selectedAdjustmentPresetID = ""
  @State private var adjustmentPresetName = ""
  @State private var localAdjustmentSettings = ImageAdjustmentSettings()
  @State private var renderedPreview: NSImage?
  @State private var isRenderedPreviewPresented = false
  @State private var isRenderingPreview = false
  @State private var comparisonShowsOriginal = false
  @State private var zoomScale = 1.0
  @State private var zoomGestureBase = 1.0
  @State private var panOffset = CGSize.zero
  @State private var panGestureBase = CGSize.zero
  @State private var actualSizeScale = 1.0
  @State private var sessionSaveTask: Task<Void, Never>?

  private let pipeline = ImageEditPipeline()
  private let previewRenderer = ImageEditPreviewRenderer()
  private let histogramAnalyzer = ImageHistogramAnalyzer()
  private let sessionStore = EditSessionStoreProvider.shared
  private let inspectorWidth: CGFloat = 360

  private var editSnapshot: ImageEditSnapshot {
    editSession.currentSnapshot
  }

  private var canEdit: Bool {
    UTType(asset.contentType)?.conforms(to: .image) == true
  }

  private var showsCropPreview: Bool {
    !isCropEditing && !editSnapshot.cropRect.isEffectivelyFull
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      HStack(spacing: 0) {
        editorCanvas
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider()
        inspector
          .frame(width: inspectorWidth)
      }
      statusBar
    }
    .frame(minWidth: 1_080, minHeight: 760)
    .task(id: asset.id) {
      await loadEditorState()
    }
    .onChange(of: editSnapshot) { _, snapshot in
      scheduleSessionSave(snapshot)
      if isRenderedPreviewPresented {
        isRenderedPreviewPresented = false
        renderedPreview = nil
      }
    }
    .onDisappear {
      sessionSaveTask?.cancel()
      if let sessionStore {
        let snapshot = editSnapshot
        Task {
          try? await sessionStore.saveImageSession(snapshot, for: asset.id)
        }
      }
    }
  }

  private var toolbar: some View {
    HStack(spacing: 12) {
      VStack(alignment: .leading, spacing: 2) {
        Text(language.editorTitle)
          .font(.headline)
        Text(asset.filename)
          .font(.caption)
          .foregroundStyle(.secondary)
          .lineLimit(1)
          .truncationMode(.middle)
      }
      .frame(maxWidth: 240, alignment: .leading)
      Spacer()
      if !toolsReady {
        Image(systemName: "wrench.and.screwdriver")
          .foregroundStyle(.orange)
          .help(language.toolsNotReady)
      }
      Button {
        undo()
      } label: {
        Image(systemName: "arrow.uturn.backward")
      }
      .disabled(!editSession.canUndo)
      .keyboardShortcut("z", modifiers: .command)
      .help(language.undo)
      Button {
        redo()
      } label: {
        Image(systemName: "arrow.uturn.forward")
      }
      .disabled(!editSession.canRedo)
      .keyboardShortcut("z", modifiers: [.command, .shift])
      .help(language.redo)
      Picker("Comparison", selection: $comparisonShowsOriginal) {
        Text(language.before).tag(true)
        Text(language.after).tag(false)
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .frame(width: 130)
      Menu {
        Button(language.fit) {
          setZoom(1)
        }
        .keyboardShortcut("0", modifiers: .command)
        Button(language.actualSize) {
          setZoom(actualSizeScale)
        }
        .keyboardShortcut("1", modifiers: .command)
        Divider()
        Button {
          setZoom(zoomScale / 1.25)
        } label: {
          Label("Zoom Out", systemImage: "minus.magnifyingglass")
        }
        .keyboardShortcut("-", modifiers: .command)
        Button {
          setZoom(zoomScale * 1.25)
        } label: {
          Label("Zoom In", systemImage: "plus.magnifyingglass")
        }
        .keyboardShortcut("+", modifiers: .command)
      } label: {
        Image(systemName: "magnifyingglass")
      }
      Button {
        isExportOptionsPresented = true
      } label: {
        Label(language.export, systemImage: "square.and.arrow.up")
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canEdit || isExporting || !toolsReady)
      .popover(isPresented: $isExportOptionsPresented, arrowEdge: .bottom) {
        ExportOptionsPopover(
          language: language,
          outputFormat: $outputFormat,
          quality: $quality,
          preset: $preset,
          maxWidth: $maxWidth,
          maxHeight: $maxHeight,
          targetSizeKB: $targetSizeKB,
          isExporting: isExporting,
          onChooseLocation: {
            isExportOptionsPresented = false
            exportEditedCopy()
          }
        )
        .frame(width: 320)
        .padding(12)
      }
      Button {
        dismiss()
      } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.bordered)
      .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, 20)
    .frame(height: 64)
  }

  private var imageAspectSize: CGSize {
    let width = CGFloat(max(asset.pixelWidth ?? 1, 1))
    let height = CGFloat(max(asset.pixelHeight ?? 1, 1))
    return CGSize(width: width, height: height)
  }

  private var layoutImageSize: CGSize {
    let base = imageAspectSize
    if editSnapshot.quarterTurns % 2 == 1 {
      return CGSize(width: base.height, height: base.width)
    }
    return base
  }

  private var editorCanvas: some View {
    GeometryReader { proxy in
      let paddedSize = CGSize(
        width: max(0, proxy.size.width - 48),
        height: max(0, proxy.size.height - 48)
      )
      let layout = EditorImageLayout(
        imageSize: layoutImageSize,
        containerSize: paddedSize
      )
      ZStack {
        Color(nsColor: .underPageBackgroundColor)
        if canEdit {
          canvasContent(size: layout.contentRect.size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(24)
            .scaleEffect(zoomScale)
            .offset(panOffset)
            .simultaneousGesture(zoomGesture)
            .simultaneousGesture(panGesture)
            .onAppear {
              updateActualSizeScale(for: layout.contentRect.size)
            }
            .onChange(of: layout.contentRect.size) { _, size in
              updateActualSizeScale(for: size)
            }
        } else {
          ContentUnavailableView(
            "Preview unavailable",
            systemImage: "photo.badge.exclamationmark"
          )
        }
      }
    }
  }

  @ViewBuilder
  private func canvasContent(size: CGSize) -> some View {
    if comparisonShowsOriginal {
      AssetImageView(
        asset: asset,
        enrichment: nil,
        maxPixelSize: 1_800,
        contentMode: .fit
      )
      .frame(width: size.width, height: size.height)
    } else if isRenderedPreviewPresented, let renderedPreview {
      Image(nsImage: renderedPreview)
        .resizable()
        .interpolation(.high)
        .scaledToFit()
        .frame(width: size.width, height: size.height)
        .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    } else {
      editableCanvas(size: size)
    }
  }

  private func editableCanvas(size: CGSize) -> some View {
    let sourceFrameSize =
      editSnapshot.quarterTurns % 2 == 1
      ? CGSize(width: size.height, height: size.width)
      : size

    return ZStack {
      AssetImageView(
        asset: asset,
        enrichment: nil,
        maxPixelSize: 1_800,
        contentMode: .fit
      )
      .frame(width: sourceFrameSize.width, height: sourceFrameSize.height)
      .brightness(editSnapshot.adjustments.exposure * 0.32)
      .contrast(1 + editSnapshot.adjustments.contrast)
      .saturation(1 + editSnapshot.adjustments.saturation)
      .hueRotation(.degrees(editSnapshot.adjustments.warmth * -12))
      .scaleEffect(x: editSnapshot.flippedHorizontally ? -1 : 1, y: 1)
      .rotationEffect(.degrees(Double(editSnapshot.quarterTurns * 90)))
    }
    .frame(width: size.width, height: size.height)
    .mask {
      if showsCropPreview {
        Rectangle().path(in: editSnapshot.cropRect.pixelRect(in: size))
      } else {
        Rectangle()
      }
    }
    .clipped()
    .background(Color.black.opacity(0.12))
    .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    .overlay {
      if selectedTool == .geometry && isCropEditing {
        InteractiveCropOverlay(cropRect: snapshotBinding(\.cropRect))
          .frame(width: size.width, height: size.height)
      }
      MaskBrushOverlay(
        strokes: editSnapshot.maskStrokes,
        currentStroke: currentMaskStroke
      )
      .frame(width: size.width, height: size.height)
      AnnotationCanvasOverlay(
        annotations: snapshotBinding(\.annotations),
        selectedAnnotationID: $selectedAnnotationID,
        isEditing: selectedTool == .annotate
      )
      .frame(width: size.width, height: size.height)
      if selectedTool == .mask {
        MaskPaintingSurface(
          maskStrokes: snapshotBinding(\.maskStrokes),
          currentMaskStroke: $currentMaskStroke,
          brushRadius: brushRadius,
          operation: maskOperation
        )
        .frame(width: size.width, height: size.height)
      }
    }
  }

  private var inspector: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        ImageEditorToolSelector(
          language: language,
          selection: $selectedTool,
          onSelect: { tool in
            if tool == .geometry {
              isCropEditing = true
            }
          }
        )
        Divider()
        switch selectedTool {
        case .geometry:
          geometryControls
        case .adjust:
          adjustControls
        case .annotate:
          annotateControls
        case .mask:
          maskControls
        }
        Divider()
        EditorLayerControls(
          language: language,
          layers: snapshotBinding(\.layers)
        )
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
        Text(language.exportingImage)
      } else if let exportMessage {
        Text(exportMessage)
      } else {
        Text(statusHint)
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

  private var statusHint: String {
    switch selectedTool {
    case .geometry:
      isCropEditing ? language.editorGeometryHint : language.cropAppliedHint
    case .adjust:
      language.editorAdjustHint
    case .mask:
      language.maskBrushHint
    default:
      language.editorCanvasHint
    }
  }

  private var geometryControls: some View {
    ImageGeometryInspector(
      language: language,
      cropRect: snapshotBinding(\.cropRect),
      quarterTurns: snapshotBinding(\.quarterTurns),
      flippedHorizontally: snapshotBinding(\.flippedHorizontally),
      isCropEditing: $isCropEditing
    )
  }

  private var adjustControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      ImageAdjustmentInspector(
        language: language,
        settings: snapshotBinding(\.adjustments),
        histogram: histogram,
        requiresFullRenderPreview: editSnapshot.adjustments.requiresFullRenderPreview,
        isRenderingPreview: isRenderingPreview,
        isRenderedPreviewPresented: isRenderedPreviewPresented,
        isRenderPreviewDisabled: comparisonShowsOriginal,
        presets: ImageAdjustmentPreset.builtIn + customAdjustmentPresets,
        selectedPresetID: $selectedAdjustmentPresetID,
        presetName: $adjustmentPresetName,
        onSavePreset: saveAdjustmentPreset,
        onRenderPreview: toggleRenderedPreview
      )
      Button(language.reset) {
        updateSnapshot { $0.adjustments = .neutral }
        selectedAdjustmentPresetID = ""
      }
    }
  }

  private var annotateControls: some View {
    ImageAnnotationInspector(
      language: language,
      annotations: snapshotBinding(\.annotations),
      selectedAnnotationID: $selectedAnnotationID
    )
  }

  private var maskControls: some View {
    ImageMaskInspector(
      language: language,
      maskStrokes: snapshotBinding(\.maskStrokes),
      localAdjustments: snapshotBinding(\.localAdjustments),
      currentMaskStroke: $currentMaskStroke,
      brushRadius: $brushRadius,
      maskOperation: $maskOperation,
      localAdjustmentSettings: $localAdjustmentSettings
    )
  }

  private func snapshotBinding<T>(_ keyPath: WritableKeyPath<ImageEditSnapshot, T>) -> Binding<T> {
    Binding(
      get: { editSnapshot[keyPath: keyPath] },
      set: { newValue in
        updateSnapshot { $0[keyPath: keyPath] = newValue }
      }
    )
  }

  private func updateSnapshot(_ mutate: (inout ImageEditSnapshot) -> Void) {
    editSession.update(mutate)
  }

  private func undo() {
    editSession.undo()
    currentMaskStroke = nil
  }

  private func redo() {
    editSession.redo()
    currentMaskStroke = nil
  }

  private func toggleRenderedPreview() {
    if isRenderedPreviewPresented {
      isRenderedPreviewPresented = false
      renderedPreview = nil
    } else {
      renderPixelPreview()
    }
  }

  private func exportEditedCopy() {
    let panel = NSSavePanel()
    panel.title = language.saveEditedCopy
    panel.nameFieldStringValue =
      "\(asset.url.deletingPathExtension().lastPathComponent)-edited.\(outputFormat.rawValue)"
    panel.allowedContentTypes = [uti(for: outputFormat)]
    guard panel.runModal() == .OK, let outputURL = panel.url else { return }
    guard outputURL.standardizedFileURL != asset.url.standardizedFileURL else {
      exportMessage = language.originalFileProtected
      return
    }

    let snapshot = editSnapshot
    let request = ImageEditRequest(
      sourceURL: asset.url,
      outputURL: outputURL,
      cropRect: snapshot.cropRect,
      quarterTurns: snapshot.quarterTurns,
      flippedHorizontally: snapshot.flippedHorizontally,
      adjustments: snapshot.adjustments,
      annotations: snapshot.annotations,
      maskStrokes: snapshot.maskStrokes,
      localAdjustments: snapshot.localAdjustments,
      layers: snapshot.layers,
      format: outputFormat,
      quality: Int(quality),
      preset: preset,
      maxWidth: Int(maxWidth),
      maxHeight: Int(maxHeight),
      targetSizeBytes: Int(targetSizeKB).map { $0 * 1_024 }
    )

    isExporting = true
    exportMessage = nil
    Task { @MainActor in
      do {
        let result = try await pipeline.export(request)
        lastExportedURL = result.outputURL
        exportMessage = "\(language.editorExported) · \(formattedBytes(result.outputSize))"
        onExport(result, request)
      } catch {
        exportMessage = "\(language.editorExportFailed): \(error.localizedDescription)"
      }
      isExporting = false
    }
  }

  private func uti(for format: PicxOutputFormat) -> UTType {
    switch format {
    case .webp: UTType(filenameExtension: "webp") ?? .data
    case .avif: UTType(filenameExtension: "avif") ?? .data
    case .jpg: .jpeg
    case .png: .png
    }
  }

  private func formattedBytes(_ value: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
  }

  private var zoomGesture: some Gesture {
    MagnificationGesture()
      .onChanged { value in
        zoomScale = min(max(zoomGestureBase * value, 0.25), 8)
      }
      .onEnded { _ in
        zoomGestureBase = zoomScale
      }
  }

  private var panGesture: some Gesture {
    DragGesture(minimumDistance: 4)
      .onChanged { value in
        guard zoomScale > 1, selectedTool == .adjust else { return }
        panOffset = CGSize(
          width: panGestureBase.width + value.translation.width,
          height: panGestureBase.height + value.translation.height
        )
      }
      .onEnded { _ in
        panGestureBase = panOffset
      }
  }

  private func setZoom(_ value: Double) {
    zoomScale = min(max(value, 0.25), 8)
    zoomGestureBase = zoomScale
    if zoomScale <= 1 {
      panOffset = .zero
      panGestureBase = .zero
    }
  }

  private func updateActualSizeScale(for canvasSize: CGSize) {
    guard canvasSize.width > 0, canvasSize.height > 0 else { return }
    actualSizeScale = min(
      8,
      max(
        0.25,
        max(
          imageAspectSize.width / canvasSize.width,
          imageAspectSize.height / canvasSize.height
        )
      )
    )
  }

  private func renderPixelPreview() {
    isRenderingPreview = true
    let snapshot = editSnapshot
    let sourceURL = asset.url
    Task {
      do {
        let image = try await Task.detached(priority: .userInitiated) {
          try previewRenderer.renderPreviewImage(
            sourceURL: sourceURL,
            snapshot: snapshot
          )
        }.value
        renderedPreview = image
        isRenderedPreviewPresented = true
        exportMessage = language.previewActive
      } catch {
        exportMessage = "\(language.previewFailed): \(error.localizedDescription)"
      }
      isRenderingPreview = false
    }
  }

  private func loadEditorState() async {
    if let sessionStore {
      if let saved = try? await sessionStore.imageSession(for: asset.id) {
        var restored = ImageEditSession(
          initialSnapshot: ImageEditSnapshot.defaultInitial
        )
        restored.replaceCurrent(with: saved)
        editSession = restored
      }
      customAdjustmentPresets =
        (try? await sessionStore.adjustmentPresets()) ?? []
    }
    histogram = try? await Task.detached(priority: .utility) {
      try histogramAnalyzer.analyze(url: asset.url)
    }.value
  }

  private func scheduleSessionSave(_ snapshot: ImageEditSnapshot) {
    guard let sessionStore else { return }
    sessionSaveTask?.cancel()
    sessionSaveTask = Task {
      try? await Task.sleep(for: .milliseconds(350))
      guard !Task.isCancelled else { return }
      try? await sessionStore.saveImageSession(snapshot, for: asset.id)
    }
  }

  private func saveAdjustmentPreset() {
    guard let sessionStore else { return }
    let name = adjustmentPresetName.trimmingCharacters(in: .whitespaces)
    guard !name.isEmpty else { return }
    let preset = ImageAdjustmentPreset(
      id: UUID().uuidString,
      name: name,
      settings: editSnapshot.adjustments
    )
    customAdjustmentPresets.append(preset)
    selectedAdjustmentPresetID = preset.id
    adjustmentPresetName = ""
    Task {
      try? await sessionStore.saveAdjustmentPresets(customAdjustmentPresets)
    }
  }

}
