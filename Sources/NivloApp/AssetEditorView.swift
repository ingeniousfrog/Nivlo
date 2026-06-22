import AppKit
import NivloDomain
import NivloImaging
import SwiftUI
import UniformTypeIdentifiers

private enum ImageEditorTab: String, CaseIterable, Identifiable {
  case geometry
  case adjust
  case annotate
  case mask
  case export

  var id: String { rawValue }

  func title(language: NivloLanguage) -> String {
    switch self {
    case .geometry: language.tabGeometry
    case .adjust: language.tabAdjust
    case .annotate: language.tabAnnotate
    case .mask: language.tabMask
    case .export: language.tabExport
    }
  }

  var icon: String {
    switch self {
    case .geometry: "crop.rotate"
    case .adjust: "slider.horizontal.3"
    case .annotate: "pencil.and.outline"
    case .mask: "paintbrush.pointed"
    case .export: "square.and.arrow.up"
    }
  }
}

struct AssetEditorView: View {
  let asset: ImageAsset
  let language: NivloLanguage
  let toolsReady: Bool
  let onExport: (PicxOptimizeResult, ImageEditRequest) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var selectedTab: ImageEditorTab = .geometry
  @State private var appliedSnapshot = ImageEditSnapshot()
  @State private var draftCropRect = NormalizedCropRect.full
  @State private var draftQuarterTurns = 0
  @State private var draftFlippedHorizontally = false
  @State private var draftAdjustments = ImageAdjustmentSettings.neutral
  @State private var annotations: [ImageAnnotation] = []
  @State private var maskStrokes: [MaskStroke] = []
  @State private var currentMaskStroke: MaskStroke?
  @State private var brushRadius = 0.035
  @State private var layers = EditorLayer.defaults
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

  private let pipeline = ImageEditPipeline()
  private let previewRenderer = ImageEditPreviewRenderer()
  private let sidebarWidth: CGFloat = 220
  private let inspectorWidth: CGFloat = 340

  private var canEdit: Bool {
    UTType(asset.contentType)?.conforms(to: .image) == true
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      HStack(spacing: 0) {
        tabSidebar
        Divider()
        editorCanvas
          .frame(maxWidth: .infinity, maxHeight: .infinity)
        Divider()
        inspector
          .frame(width: inspectorWidth)
      }
      statusBar
    }
    .frame(minWidth: 1_160, minHeight: 780)
    .onAppear {
      syncDraftFromApplied()
    }
    .onChange(of: selectedTab) { _, _ in
      if !isPreviewing {
        previewImage = nil
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
        selectedTab = .export
        exportEditedCopy()
      } label: {
        Label(language.saveEditedCopy, systemImage: "square.and.arrow.up")
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canEdit || isExporting || !toolsReady)
      Button { dismiss() } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.bordered)
      .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private var tabSidebar: some View {
    List(selection: $selectedTab) {
      ForEach(ImageEditorTab.allCases) { tab in
        Label(tab.title(language: language), systemImage: tab.icon)
          .tag(tab)
      }
    }
    .listStyle(.sidebar)
    .frame(width: sidebarWidth)
  }

  private var imageAspectSize: CGSize {
    let width = CGFloat(max(asset.pixelWidth ?? 1, 1))
    let height = CGFloat(max(asset.pixelHeight ?? 1, 1))
    return CGSize(width: width, height: height)
  }

  private var layoutImageSize: CGSize {
    let base = imageAspectSize
    if displayQuarterTurns % 2 == 1 {
      return CGSize(width: base.height, height: base.width)
    }
    return base
  }

  private func updateAppliedSnapshot(_ mutate: (inout ImageEditSnapshot) -> Void) {
    var snapshot = appliedSnapshot
    mutate(&snapshot)
    appliedSnapshot = snapshot
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
            ZStack {
              AssetImageView(
                asset: asset,
                enrichment: nil,
                maxPixelSize: 1_800,
                contentMode: .fit
              )
              .frame(width: layout.contentRect.width, height: layout.contentRect.height)
              .rotationEffect(.degrees(Double(displayQuarterTurns * 90)))
              .scaleEffect(x: displayFlippedHorizontally ? -1 : 1, y: 1)
              .overlay {
                if selectedTab == .geometry {
                  InteractiveCropOverlay(
                    cropRect: $draftCropRect,
                    contentRect: CGRect(
                      origin: .zero,
                      size: layout.contentRect.size
                    )
                  )
                }
                if selectedTab == .mask {
                  MaskBrushOverlay(
                    strokes: maskStrokes,
                    currentStroke: currentMaskStroke,
                    brushRadius: brushRadius
                  )
                  .allowsHitTesting(false)
                }
              }
              .overlay {
                if selectedTab == .mask, !isPreviewing {
                  MaskPaintingSurface(
                    maskStrokes: $maskStrokes,
                    currentMaskStroke: $currentMaskStroke,
                    brushRadius: brushRadius
                  )
                }
              }
              .position(
                x: layout.contentRect.midX,
                y: layout.contentRect.midY
              )
            }
            .frame(width: paddedSize.width, height: paddedSize.height)
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

  private var displayQuarterTurns: Int {
    selectedTab == .geometry ? draftQuarterTurns : appliedSnapshot.quarterTurns
  }

  private var displayFlippedHorizontally: Bool {
    selectedTab == .geometry ? draftFlippedHorizontally : appliedSnapshot.flippedHorizontally
  }

  private var inspector: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 16) {
        Text(selectedTab.title(language: language))
          .font(.title3.weight(.semibold))

        switch selectedTab {
        case .geometry:
          geometryControls
        case .adjust:
          adjustControls
        case .annotate:
          annotateControls
        case .mask:
          maskControls
        case .export:
          exportControls
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
    switch selectedTab {
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
        Button { draftQuarterTurns = normalizedQuarterTurns(draftQuarterTurns - 1) } label: {
          Label(language.rotateLeft, systemImage: "rotate.left")
        }
        Button { draftQuarterTurns = normalizedQuarterTurns(draftQuarterTurns + 1) } label: {
          Label(language.rotateRight, systemImage: "rotate.right")
        }
      }
      Button { draftFlippedHorizontally.toggle() } label: {
        Label(language.flipHorizontal, systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
      }

      actionButtons(
        apply: applyGeometry,
        preview: { runPreview(includeDraft: true, tab: .geometry) },
        revert: revertGeometry
      )
    }
  }

  private var cropSizeReadout: some View {
    let crop = draftCropRect.clamped()
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

      sliderRow(language.adjustExposure, value: $draftAdjustments.exposure, range: -1...1)
      sliderRow(language.adjustContrast, value: $draftAdjustments.contrast, range: -0.5...0.5)
      sliderRow(language.adjustSaturation, value: $draftAdjustments.saturation, range: -0.5...0.5)
      sliderRow(language.adjustWarmth, value: $draftAdjustments.warmth, range: -1...1)

      actionButtons(
        apply: applyAdjustments,
        preview: { runPreview(includeDraft: true, tab: .adjust) },
        revert: revertAdjustments
      )
    }
  }

  private var annotateControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(language.addTextAnnotation) {
        annotations.append(
          ImageAnnotation(
            kind: .text,
            text: "Note",
            normalizedRect: NormalizedCropRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)
          )
        )
      }
      Button(language.addRectangleAnnotation) {
        annotations.append(
          ImageAnnotation(
            kind: .rectangle,
            normalizedRect: NormalizedCropRect(x: 0.2, y: 0.2, width: 0.3, height: 0.2)
          )
        )
      }
      Button(language.addArrowAnnotation) {
        annotations.append(
          ImageAnnotation(
            kind: .arrow,
            normalizedRect: NormalizedCropRect(x: 0.15, y: 0.15, width: 0.35, height: 0.35)
          )
        )
      }
      if !annotations.isEmpty {
        Button(language.clearAnnotations, role: .destructive) {
          annotations.removeAll()
        }
      }
      actionButtons(
        apply: {
          updateAppliedSnapshot { $0.annotations = annotations }
          exportMessage = language.changesApplied
          runPreview(includeDraft: false, tab: .annotate)
        },
        preview: { runPreview(includeDraft: false, tab: .annotate) },
        revert: {
          annotations = appliedSnapshot.annotations
          exportMessage = nil
          exitPreview()
        }
      )
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

      Text("\(language.maskStrokeCount): \(maskStrokes.count)")
        .font(.caption)
        .foregroundStyle(.secondary)

      if !maskStrokes.isEmpty {
        Button(language.clearMask, role: .destructive) {
          maskStrokes.removeAll()
          currentMaskStroke = nil
        }
      }

      actionButtons(
        apply: applyMask,
        preview: { runPreview(includeDraft: true, tab: .mask) },
        revert: revertMask
      )
    }
  }

  private func actionButtons(
    apply: @escaping () -> Void,
    preview: @escaping () -> Void,
    revert: @escaping () -> Void
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 8) {
        Button(language.applyChanges) {
          apply()
        }
        .buttonStyle(.borderedProminent)
        Button(language.previewChanges) {
          preview()
        }
        .buttonStyle(.bordered)
        .disabled(isRenderingPreview)
      }
      Button(language.revertChanges) {
        revert()
      }
      .buttonStyle(.bordered)
    }
    .padding(.top, 4)
  }

  private var exportControls: some View {
    VStack(alignment: .leading, spacing: 14) {
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
        exportEditedCopy()
      } label: {
        Label(language.saveEditedCopy, systemImage: "square.and.arrow.up")
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canEdit || isExporting || !toolsReady)
    }
  }

  private func sliderRow(
    _ title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
      Slider(value: value, in: range)
    }
  }

  private func syncDraftFromApplied() {
    draftCropRect = appliedSnapshot.cropRect
    draftQuarterTurns = appliedSnapshot.quarterTurns
    draftFlippedHorizontally = appliedSnapshot.flippedHorizontally
    draftAdjustments = appliedSnapshot.adjustments
    annotations = appliedSnapshot.annotations
    maskStrokes = appliedSnapshot.maskStrokes
  }

  private func applyGeometry() {
    updateAppliedSnapshot { snapshot in
      snapshot.cropRect = draftCropRect.clamped()
      snapshot.quarterTurns = draftQuarterTurns
      snapshot.flippedHorizontally = draftFlippedHorizontally
    }
    exportMessage = language.changesApplied
    runPreview(includeDraft: false, tab: .geometry)
  }

  private func revertGeometry() {
    draftCropRect = appliedSnapshot.cropRect
    draftQuarterTurns = appliedSnapshot.quarterTurns
    draftFlippedHorizontally = appliedSnapshot.flippedHorizontally
    exportMessage = nil
    exitPreview()
  }

  private func applyAdjustments() {
    updateAppliedSnapshot { $0.adjustments = draftAdjustments }
    exportMessage = language.changesApplied
    runPreview(includeDraft: false, tab: .adjust)
  }

  private func revertAdjustments() {
    draftAdjustments = appliedSnapshot.adjustments
    exportMessage = nil
    exitPreview()
  }

  private func applyMask() {
    updateAppliedSnapshot { $0.maskStrokes = maskStrokes }
    exportMessage = language.changesApplied
    runPreview(includeDraft: false, tab: .mask)
  }

  private func revertMask() {
    maskStrokes = appliedSnapshot.maskStrokes
    currentMaskStroke = nil
    exportMessage = nil
    exitPreview()
  }

  private func previewSnapshot(includeDraft: Bool, tab: ImageEditorTab) -> ImageEditSnapshot {
    var snapshot = appliedSnapshot
    snapshot.annotations = annotations
    snapshot.maskStrokes = maskStrokes
    snapshot.layers = layers
    if includeDraft {
      switch tab {
      case .geometry:
        snapshot.cropRect = draftCropRect.clamped()
        snapshot.quarterTurns = draftQuarterTurns
        snapshot.flippedHorizontally = draftFlippedHorizontally
      case .adjust:
        snapshot.adjustments = draftAdjustments
      case .mask:
        snapshot.maskStrokes = maskStrokes
      default:
        break
      }
    }
    return snapshot
  }

  private func runPreview(includeDraft: Bool, tab: ImageEditorTab) {
    isRenderingPreview = true
    let snapshot = previewSnapshot(includeDraft: includeDraft, tab: tab)
    Task {
      do {
        let image = try await Task.detached(priority: .userInitiated) {
          try previewRenderer.renderPreviewImage(sourceURL: asset.url, snapshot: snapshot)
        }.value
        previewImage = image
        isPreviewing = true
        exportMessage = nil
      } catch {
        exportMessage = "\(language.previewFailed): \(error.localizedDescription)"
      }
      isRenderingPreview = false
    }
  }

  private func exitPreview() {
    isPreviewing = false
    previewImage = nil
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

    var snapshot = appliedSnapshot
    snapshot.annotations = annotations
    snapshot.maskStrokes = maskStrokes
    snapshot.layers = layers

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
    Task {
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

// MARK: - Image layout

private struct EditorImageLayout {
  let imageSize: CGSize
  let containerSize: CGSize

  var contentRect: CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else {
      return CGRect(origin: .zero, size: containerSize)
    }
    let scale = min(
      containerSize.width / imageSize.width,
      containerSize.height / imageSize.height
    )
    let fitted = CGSize(
      width: imageSize.width * scale,
      height: imageSize.height * scale
    )
    return CGRect(
      x: (containerSize.width - fitted.width) / 2,
      y: (containerSize.height - fitted.height) / 2,
      width: fitted.width,
      height: fitted.height
    )
  }
}

// MARK: - Crop overlay

private enum CropHandle {
  case move
  case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
}

private struct InteractiveCropOverlay: View {
  @Binding var cropRect: NormalizedCropRect
  let contentRect: CGRect

  @State private var activeHandle: CropHandle?
  @State private var dragStartRect = NormalizedCropRect.full

  var body: some View {
    GeometryReader { proxy in
      let canvasSize = proxy.size
      let rect = pixelRect(for: cropRect.clamped(), in: contentRect.size)

      ZStack {
        Path { path in
          path.addRect(CGRect(origin: .zero, size: canvasSize))
          path.addRect(rect)
        }
        .fill(Color.black.opacity(0.42), style: FillStyle(eoFill: true))
        .allowsHitTesting(false)

        Rectangle()
          .strokeBorder(Color.yellow, lineWidth: 2)
          .background(Color.yellow.opacity(0.08))
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
          .contentShape(Rectangle())
          .gesture(moveGesture(canvasSize: contentRect.size))
          .zIndex(0)

        ForEach(handlePositions(in: rect), id: \.handle) { item in
          Circle()
            .fill(Color.yellow)
            .frame(width: 14, height: 14)
            .overlay(Circle().stroke(Color.black.opacity(0.35), lineWidth: 1))
            .position(item.point)
            .contentShape(Circle())
            .highPriorityGesture(
              DragGesture(minimumDistance: 0)
                .onChanged { value in
                  if activeHandle == nil {
                    activeHandle = item.handle
                    dragStartRect = cropRect.clamped()
                  }
                  guard activeHandle == item.handle else { return }
                  cropRect = resizedRect(
                    from: dragStartRect,
                    handle: item.handle,
                    translation: value.translation,
                    in: contentRect.size
                  )
                }
                .onEnded { _ in
                  activeHandle = nil
                  cropRect = cropRect.clamped()
                }
            )
            .zIndex(1)
        }
      }
    }
  }

  private func moveGesture(canvasSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if activeHandle == nil {
          activeHandle = .move
          dragStartRect = cropRect.clamped()
        }
        guard activeHandle == .move else { return }
        let dx = value.translation.width / canvasSize.width
        let dy = value.translation.height / canvasSize.height
        cropRect = NormalizedCropRect(
          x: min(max(0, dragStartRect.x + dx), 1 - dragStartRect.width),
          y: min(max(0, dragStartRect.y + dy), 1 - dragStartRect.height),
          width: dragStartRect.width,
          height: dragStartRect.height
        )
      }
      .onEnded { _ in
        activeHandle = nil
        cropRect = cropRect.clamped()
      }
  }

  private func pixelRect(for crop: NormalizedCropRect, in size: CGSize) -> CGRect {
    CGRect(
      x: crop.x * size.width,
      y: crop.y * size.height,
      width: crop.width * size.width,
      height: crop.height * size.height
    )
  }

  private func handlePositions(in rect: CGRect) -> [(handle: CropHandle, point: CGPoint)] {
    [
      (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
      (.top, CGPoint(x: rect.midX, y: rect.minY)),
      (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
      (.right, CGPoint(x: rect.maxX, y: rect.midY)),
      (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
      (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
      (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
      (.left, CGPoint(x: rect.minX, y: rect.midY)),
    ]
  }

  private func resizedRect(
    from start: NormalizedCropRect,
    handle: CropHandle,
    translation: CGSize,
    in size: CGSize
  ) -> NormalizedCropRect {
    let dx = translation.width / size.width
    let dy = translation.height / size.height
    let minSize = 0.05
    var x = start.x
    var y = start.y
    var width = start.width
    var height = start.height

    switch handle {
    case .move:
      break
    case .topLeft:
      x = start.x + dx
      y = start.y + dy
      width = start.width - dx
      height = start.height - dy
    case .top:
      y = start.y + dy
      height = start.height - dy
    case .topRight:
      y = start.y + dy
      width = start.width + dx
      height = start.height - dy
    case .right:
      width = start.width + dx
    case .bottomRight:
      width = start.width + dx
      height = start.height + dy
    case .bottom:
      height = start.height + dy
    case .bottomLeft:
      x = start.x + dx
      width = start.width - dx
      height = start.height + dy
    case .left:
      x = start.x + dx
      width = start.width - dx
    }

    if width < minSize {
      if handle == .left || handle == .topLeft || handle == .bottomLeft {
        x = start.x + start.width - minSize
      }
      width = minSize
    }
    if height < minSize {
      if handle == .top || handle == .topLeft || handle == .topRight {
        y = start.y + start.height - minSize
      }
      height = minSize
    }

    return NormalizedCropRect(
      x: min(max(0, x), 1 - width),
      y: min(max(0, y), 1 - height),
      width: min(width, 1),
      height: min(height, 1)
    ).clamped()
  }
}

// MARK: - Mask brush overlay

private struct MaskBrushOverlay: View {
  let strokes: [MaskStroke]
  let currentStroke: MaskStroke?
  let brushRadius: Double

  var body: some View {
    Canvas { context, canvasSize in
      let allStrokes = strokes + (currentStroke.map { [$0] } ?? [])
      for stroke in allStrokes where stroke.points.count >= 1 {
        let lineWidth = max(
          6,
          CGFloat(stroke.brushRadius) * min(canvasSize.width, canvasSize.height) * 2
        )
        if stroke.points.count == 1, let point = stroke.points.first {
          let center = pointLocation(point, in: canvasSize)
          let dot = CGRect(
            x: center.x - lineWidth / 2,
            y: center.y - lineWidth / 2,
            width: lineWidth,
            height: lineWidth
          )
          context.fill(Path(ellipseIn: dot), with: .color(.red.opacity(0.55)))
          continue
        }
        var path = Path()
        let first = stroke.points[0]
        path.move(to: pointLocation(first, in: canvasSize))
        for point in stroke.points.dropFirst() {
          path.addLine(to: pointLocation(point, in: canvasSize))
        }
        context.stroke(
          path,
          with: .color(.red.opacity(0.55)),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
      }
    }
    .allowsHitTesting(false)
  }

  private func pointLocation(_ point: MaskBrushPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: point.x * size.width, y: point.y * size.height)
  }
}

private struct MaskPaintingSurface: View {
  @Binding var maskStrokes: [MaskStroke]
  @Binding var currentMaskStroke: MaskStroke?
  let brushRadius: Double

  var body: some View {
    GeometryReader { proxy in
      Color.clear
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              let point = normalizedPoint(
                location: value.location,
                in: proxy.size
              )
              if currentMaskStroke == nil {
                currentMaskStroke = MaskStroke(points: [point], brushRadius: brushRadius)
              } else if var stroke = currentMaskStroke {
                if let last = stroke.points.last {
                  let interpolated = interpolatedPoints(from: last, to: point, brushRadius: brushRadius)
                  stroke.points.append(contentsOf: interpolated)
                } else {
                  stroke.points.append(point)
                }
                stroke.brushRadius = brushRadius
                currentMaskStroke = stroke
              }
            }
            .onEnded { _ in
              if let stroke = currentMaskStroke, !stroke.points.isEmpty {
                maskStrokes.append(stroke)
              }
              currentMaskStroke = nil
            }
        )
    }
  }

  private func normalizedPoint(location: CGPoint, in size: CGSize) -> MaskBrushPoint {
    MaskBrushPoint(
      x: Double(min(max(0, location.x / size.width), 1)),
      y: Double(min(max(0, location.y / size.height), 1))
    )
  }

  private func interpolatedPoints(
    from start: MaskBrushPoint,
    to end: MaskBrushPoint,
    brushRadius: Double
  ) -> [MaskBrushPoint] {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let distance = hypot(dx, dy)
    let step = max(brushRadius / 4, 0.004)
    guard distance > step else { return [end] }

    var points: [MaskBrushPoint] = []
    var traveled = step
    while traveled < distance {
      let t = traveled / distance
      points.append(
        MaskBrushPoint(
          x: start.x + dx * t,
          y: start.y + dy * t
        )
      )
      traveled += step
    }
    points.append(end)
    return points
  }
}
