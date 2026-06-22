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

private extension ImageEditSnapshot {
  static let defaultInitial = ImageEditSnapshot(
    cropRect: NormalizedCropRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9)
  )
}

struct AssetEditorView: View {
  let asset: ImageAsset
  let language: NivloLanguage
  let toolsReady: Bool
  let onExport: (PicxOptimizeResult, ImageEditRequest) -> Void

  @Environment(\.dismiss) private var dismiss
  @State private var selectedTool: ImageEditorTool = .geometry
  @State private var editSnapshot = ImageEditSnapshot.defaultInitial
  @State private var checkpointSnapshot = ImageEditSnapshot.defaultInitial
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
  @State private var isExportOptionsPresented = false

  private let pipeline = ImageEditPipeline()
  private let previewRenderer = ImageEditPreviewRenderer()
  private let toolRailWidth: CGFloat = 64
  private let inspectorWidth: CGFloat = 340

  private var canEdit: Bool {
    UTType(asset.contentType)?.conforms(to: .image) == true
  }

  var body: some View {
    VStack(spacing: 0) {
      toolbar
      Divider()
      HStack(spacing: 0) {
        toolRail
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
    .onChange(of: selectedTool) { _, _ in
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
      Button { dismiss() } label: {
        Image(systemName: "xmark")
      }
      .buttonStyle(.bordered)
      .keyboardShortcut(.cancelAction)
    }
    .padding(.horizontal, 20)
    .padding(.vertical, 14)
  }

  private var toolRail: some View {
    List(selection: $selectedTool) {
      ForEach(ImageEditorTool.allCases) { tool in
        Label {
          EmptyView()
        } icon: {
          Image(systemName: tool.icon)
            .font(.title3)
            .frame(maxWidth: .infinity)
        }
        .tag(tool)
        .help(tool.title(language: language))
      }
    }
    .listStyle(.sidebar)
    .frame(width: toolRailWidth)
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
            ZStack {
              AssetImageView(
                asset: asset,
                enrichment: nil,
                maxPixelSize: 1_800,
                contentMode: .fit
              )
              .frame(width: layout.contentRect.width, height: layout.contentRect.height)
              .rotationEffect(.degrees(Double(editSnapshot.quarterTurns * 90)))
              .scaleEffect(x: editSnapshot.flippedHorizontally ? -1 : 1, y: 1)
              .overlay {
                if selectedTool == .geometry {
                  InteractiveCropOverlay(
                    cropRect: snapshotBinding(\.cropRect),
                    contentRect: CGRect(origin: .zero, size: layout.contentRect.size)
                  )
                }
                if selectedTool == .mask {
                  MaskBrushOverlay(
                    strokes: editSnapshot.maskStrokes,
                    currentStroke: currentMaskStroke,
                    brushRadius: brushRadius
                  )
                  .allowsHitTesting(false)
                }
              }
              .overlay {
                if selectedTool == .mask, !isPreviewing {
                  MaskPaintingSurface(
                    maskStrokes: snapshotBinding(\.maskStrokes),
                    currentMaskStroke: $currentMaskStroke,
                    brushRadius: brushRadius
                  )
                }
              }
            }
            .frame(width: layout.contentRect.width, height: layout.contentRect.height)
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

  private var inspector: some View {
    VStack(spacing: 0) {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(selectedTool.title(language: language))
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

  private var previewRevertButtons: some View {
    VStack(alignment: .leading, spacing: 8) {
      Button(language.previewChanges) {
        runPreview()
      }
      .buttonStyle(.borderedProminent)
      .disabled(isRenderingPreview)
      Button(language.revertChanges) {
        revertEdits()
      }
      .buttonStyle(.bordered)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
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
        Label(language.flipHorizontal, systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
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
    var snapshot = editSnapshot
    mutate(&snapshot)
    editSnapshot = snapshot
  }

  private func runPreview() {
    isRenderingPreview = true
    let snapshot = editSnapshot
    Task { @MainActor in
      do {
        let image = try await Task.detached(priority: .userInitiated) {
          try previewRenderer.renderPreviewImage(sourceURL: asset.url, snapshot: snapshot)
        }.value
        previewImage = image
        isPreviewing = true
        checkpointSnapshot = snapshot
        exportMessage = nil
      } catch {
        exportMessage = "\(language.previewFailed): \(error.localizedDescription)"
      }
      isRenderingPreview = false
    }
  }

  private func revertEdits() {
    editSnapshot = checkpointSnapshot
    currentMaskStroke = nil
    exportMessage = nil
    exitPreview()
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
            .frame(width: 18, height: 18)
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
