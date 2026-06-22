import AppKit
import NivloDomain
import NivloImaging
import SwiftUI
import UniformTypeIdentifiers

private enum ImageEditorTool: String, CaseIterable, Identifiable {
  case geometry
  case adjust
  case annotate
  case mask

  var id: String { rawValue }

  func title(language: NivloLanguage) -> String {
    switch self {
    case .geometry: language.tabGeometry
    case .adjust: language.tabAdjust
    case .annotate: language.tabAnnotate
    case .mask: language.tabMask
    }
  }

  var icon: String {
    switch self {
    case .geometry: "crop.rotate"
    case .adjust: "slider.horizontal.3"
    case .annotate: "pencil.and.outline"
    case .mask: "paintbrush.pointed"
    }
  }
}

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
  @State private var currentMaskStroke: MaskStroke?
  @State private var brushRadius = 0.035
  @State private var outputFormat: PicxOutputFormat = .webp
  @State private var quality = 82.0
  @State private var preset: PicxPreset = .web
  @State private var maxWidth = ""
  @State private var maxHeight = ""
  @State private var targetSizeKB = ""
  @State private var exportMessage: String?
  @State private var lastExportedURL: URL?
  @State private var isExporting = false
  @State private var isPreviewing = false
  @State private var isRenderingPreview = false
  @State private var previewImage: NSImage?
  @State private var previewTask: Task<Void, Never>?
  @State private var previewRequestID = UUID()
  @State private var isExportOptionsPresented = false

  private let pipeline = ImageEditPipeline()
  private let previewRenderer = ImageEditPreviewRenderer()
  private let inspectorWidth: CGFloat = 360

  private var editSnapshot: ImageEditSnapshot {
    editSession.currentSnapshot
  }

  private var canEdit: Bool {
    UTType(asset.contentType)?.conforms(to: .image) == true
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
    .onDisappear {
      previewTask?.cancel()
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
      .frame(maxWidth: 360, alignment: .leading)
      Spacer()
      if isPreviewing {
        Label(language.previewActive, systemImage: "eye.fill")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
      if !toolsReady {
        Label(language.toolsNotReady, systemImage: "wrench.and.screwdriver")
          .font(.caption)
          .foregroundStyle(.orange)
      }
      Button {
        isExportOptionsPresented = true
      } label: {
        Label(language.saveEditedCopy, systemImage: "square.and.arrow.up")
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
    .padding(.vertical, 14)
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
          if isPreviewing, let previewImage {
            Image(nsImage: previewImage)
              .resizable()
              .aspectRatio(contentMode: .fit)
              .padding(24)
              .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
          } else {
            editableCanvas(size: layout.contentRect.size)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
              .padding(24)
          }
          if isRenderingPreview {
            ProgressView(language.renderingPreview)
              .padding(12)
              .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 10))
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
      .scaleEffect(x: editSnapshot.flippedHorizontally ? -1 : 1, y: 1)
      .rotationEffect(.degrees(Double(editSnapshot.quarterTurns * 90)))
    }
    .frame(width: size.width, height: size.height)
    .clipped()
    .background(Color.black.opacity(0.12))
    .shadow(color: .black.opacity(0.24), radius: 18, y: 8)
    .overlay {
      if selectedTool == .geometry {
        InteractiveCropOverlay(cropRect: snapshotBinding(\.cropRect))
          .frame(width: size.width, height: size.height)
      }
      if selectedTool == .mask {
        MaskBrushOverlay(
          strokes: editSnapshot.maskStrokes,
          currentStroke: currentMaskStroke
        )
        .frame(width: size.width, height: size.height)
        MaskPaintingSurface(
          maskStrokes: snapshotBinding(\.maskStrokes),
          currentMaskStroke: $currentMaskStroke,
          brushRadius: brushRadius
        )
        .frame(width: size.width, height: size.height)
      }
    }
  }

  private var inspector: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          toolSelector
          Divider()
          Label(
            selectedTool.title(language: language),
            systemImage: selectedTool.icon
          )
          .font(.title3.weight(.semibold))

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
      }
      Divider()
      previewRevertButtons
        .padding(20)
    }
    .background(Color(nsColor: .windowBackgroundColor))
  }

  private var toolSelector: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(language.editorTools)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)

      LazyVGrid(
        columns: [
          GridItem(.flexible(), spacing: 8),
          GridItem(.flexible(), spacing: 8),
        ],
        spacing: 8
      ) {
        ForEach(ImageEditorTool.allCases) { tool in
          Button {
            selectedTool = tool
            exitPreview()
          } label: {
            Label(tool.title(language: language), systemImage: tool.icon)
              .frame(maxWidth: .infinity, minHeight: 30, alignment: .leading)
              .contentShape(Rectangle())
          }
          .buttonStyle(.bordered)
          .tint(selectedTool == tool ? Color.accentColor : .secondary)
          .controlSize(.large)
        }
      }
    }
  }

  private var previewRevertButtons: some View {
    HStack(spacing: 10) {
      Button(language.previewChanges) {
        runPreview()
      }
      .buttonStyle(.borderedProminent)
      .disabled(isRenderingPreview)
      .frame(maxWidth: .infinity)
      Button(language.revertChanges) {
        revertEdits()
      }
      .buttonStyle(.bordered)
      .disabled(!editSession.hasChanges)
      .frame(maxWidth: .infinity)
    }
  }

  private var statusBar: some View {
    HStack(spacing: 12) {
      if isExporting {
        ProgressView().controlSize(.small)
        Text(language.exportingImage)
      } else if let exportMessage {
        Text(exportMessage)
      } else if isPreviewing {
        Text(language.previewActiveHint)
      } else {
        Text(statusHint)
      }
      Spacer()
      if isPreviewing {
        Button(language.exitPreview) {
          exitPreview()
        }
        .controlSize(.small)
      }
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
      language.editorGeometryHint
    case .adjust:
      language.editorAdjustHint
    case .mask:
      language.maskBrushHint
    default:
      language.editorCanvasHint
    }
  }

  private var geometryControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(language.editorGeometryHint)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      cropSizeReadout

      HStack(spacing: 8) {
        Button {
          updateSnapshot { $0.quarterTurns = normalizedQuarterTurns($0.quarterTurns - 1) }
        } label: {
          Label(language.rotateLeft, systemImage: "rotate.left")
        }
        Button {
          updateSnapshot { $0.quarterTurns = normalizedQuarterTurns($0.quarterTurns + 1) }
        } label: {
          Label(language.rotateRight, systemImage: "rotate.right")
        }
      }
      Button {
        updateSnapshot { $0.flippedHorizontally.toggle() }
      } label: {
        Label(
          language.flipHorizontal,
          systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
      }
      Button(language.reset) {
        updateSnapshot {
          $0.cropRect = ImageEditSnapshot.defaultInitial.cropRect
          $0.quarterTurns = 0
          $0.flippedHorizontally = false
        }
      }
    }
  }

  private var cropSizeReadout: some View {
    let crop = editSnapshot.cropRect.clamped()
    return Text(
      "\(language.cropSizeLabel): \(Int(crop.width * 100))% × \(Int(crop.height * 100))%"
    )
    .font(.caption.monospacedDigit())
    .foregroundStyle(.secondary)
  }

  private var adjustControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(language.editorAdjustHint)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      sliderRow(language.adjustExposure, keyPath: \.exposure, range: -1...1)
      sliderRow(language.adjustContrast, keyPath: \.contrast, range: -0.5...0.5)
      sliderRow(language.adjustSaturation, keyPath: \.saturation, range: -0.5...0.5)
      sliderRow(language.adjustWarmth, keyPath: \.warmth, range: -1...1)
    }
  }

  private var annotateControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(language.addTextAnnotation) {
        updateSnapshot {
          $0.annotations.append(
            ImageAnnotation(
              kind: .text,
              text: "Note",
              normalizedRect: NormalizedCropRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)
            )
          )
        }
      }
      Button(language.addRectangleAnnotation) {
        updateSnapshot {
          $0.annotations.append(
            ImageAnnotation(
              kind: .rectangle,
              normalizedRect: NormalizedCropRect(x: 0.2, y: 0.2, width: 0.3, height: 0.2)
            )
          )
        }
      }
      Button(language.addArrowAnnotation) {
        updateSnapshot {
          $0.annotations.append(
            ImageAnnotation(
              kind: .arrow,
              normalizedRect: NormalizedCropRect(x: 0.15, y: 0.15, width: 0.35, height: 0.35)
            )
          )
        }
      }
      if !editSnapshot.annotations.isEmpty {
        Button(language.clearAnnotations, role: .destructive) {
          updateSnapshot { $0.annotations.removeAll() }
        }
      }
    }
  }

  private var maskControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(language.maskBrushHint)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      Slider(value: $brushRadius, in: 0.01...0.12) {
        Text(language.maskBrushSize)
      }

      Text("\(language.maskStrokeCount): \(editSnapshot.maskStrokes.count)")
        .font(.caption)
        .foregroundStyle(.secondary)

      if !editSnapshot.maskStrokes.isEmpty {
        Button(language.clearMask, role: .destructive) {
          updateSnapshot { $0.maskStrokes.removeAll() }
          currentMaskStroke = nil
        }
      }
    }
  }

  private func sliderRow(
    _ title: String,
    keyPath: WritableKeyPath<ImageAdjustmentSettings, Double>,
    range: ClosedRange<Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
      Slider(
        value: adjustmentBinding(keyPath),
        in: range
      )
    }
  }

  private func adjustmentBinding(
    _ keyPath: WritableKeyPath<ImageAdjustmentSettings, Double>
  ) -> Binding<Double> {
    Binding(
      get: { editSnapshot.adjustments[keyPath: keyPath] },
      set: { newValue in
        updateSnapshot { $0.adjustments[keyPath: keyPath] = newValue }
      }
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
    cancelPreviewRendering()
    exitPreview()
    editSession.update(mutate)
  }

  private func runPreview() {
    cancelPreviewRendering()
    isRenderingPreview = true
    let snapshot = editSnapshot
    let requestID = UUID()
    previewRequestID = requestID
    previewTask = Task { @MainActor in
      defer {
        if previewRequestID == requestID {
          isRenderingPreview = false
          previewTask = nil
        }
      }
      do {
        let image = try await Task.detached(priority: .userInitiated) {
          try previewRenderer.renderPreviewImage(sourceURL: asset.url, snapshot: snapshot)
        }.value
        try Task.checkCancellation()
        guard previewRequestID == requestID else { return }
        previewImage = image
        isPreviewing = true
        exportMessage = nil
      } catch is CancellationError {
        return
      } catch {
        guard previewRequestID == requestID else { return }
        exportMessage = "\(language.previewFailed): \(error.localizedDescription)"
      }
    }
  }

  private func revertEdits() {
    cancelPreviewRendering()
    editSession.revert()
    currentMaskStroke = nil
    exportMessage = nil
    exitPreview()
  }

  private func exitPreview() {
    isPreviewing = false
    previewImage = nil
  }

  private func cancelPreviewRendering() {
    previewRequestID = UUID()
    previewTask?.cancel()
    previewTask = nil
    isRenderingPreview = false
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

  private func normalizedQuarterTurns(_ value: Int) -> Int {
    (value % 4 + 4) % 4
  }
}

// MARK: - Export options popover

private struct ExportOptionsPopover: View {
  let language: NivloLanguage
  @Binding var outputFormat: PicxOutputFormat
  @Binding var quality: Double
  @Binding var preset: PicxPreset
  @Binding var maxWidth: String
  @Binding var maxHeight: String
  @Binding var targetSizeKB: String
  let isExporting: Bool
  let onChooseLocation: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(language.tabExport)
        .font(.headline)

      Picker(language.exportFormat, selection: $outputFormat) {
        ForEach(PicxOutputFormat.allCases, id: \.self) { format in
          Text(format.rawValue.uppercased()).tag(format)
        }
      }
      Picker(language.exportPreset, selection: $preset) {
        ForEach(PicxPreset.allCases, id: \.self) { item in
          Text(item.rawValue).tag(item)
        }
      }
      Slider(value: $quality, in: 1...100, step: 1) {
        Text("\(language.exportQuality): \(Int(quality))")
      }
      TextField(language.maxWidth, text: $maxWidth)
      TextField(language.maxHeight, text: $maxHeight)
      TextField(language.targetSizeKB, text: $targetSizeKB)

      Button {
        onChooseLocation()
      } label: {
        Label(language.chooseExportLocation, systemImage: "folder")
      }
      .buttonStyle(.borderedProminent)
      .disabled(isExporting)
    }
  }
}
