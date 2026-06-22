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

  private let pipeline = ImageEditPipeline()
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
          editableCanvas(size: layout.contentRect.size)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            .padding(24)
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
      revertButton
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

      HStack(spacing: 6) {
        ForEach(ImageEditorTool.allCases) { tool in
          Button {
            selectedTool = tool
            if tool == .geometry {
              isCropEditing = true
            }
          } label: {
            VStack(spacing: 4) {
              Image(systemName: tool.icon)
              Text(tool.title(language: language))
                .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 42)
            .contentShape(Rectangle())
          }
          .buttonStyle(.bordered)
          .tint(selectedTool == tool ? Color.accentColor : .secondary)
        }
      }
    }
  }

  private var revertButton: some View {
    HStack {
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
    VStack(alignment: .leading, spacing: 14) {
      Text(isCropEditing ? language.editorGeometryHint : language.cropAppliedHint)
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
      if !isCropEditing, !editSnapshot.cropRect.isEffectivelyFull {
        Button(language.adjustCrop) {
          isCropEditing = true
        }
      }
      HStack(spacing: 8) {
        Button(language.applyCrop) {
          isCropEditing = false
        }
        .buttonStyle(.borderedProminent)
        .disabled(editSnapshot.cropRect.isEffectivelyFull || !isCropEditing)
        Button(language.reset) {
          resetGeometry()
        }
        .buttonStyle(.bordered)
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
      Button(language.reset) {
        updateSnapshot { $0.adjustments = .neutral }
      }
    }
  }

  private var annotateControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Button(language.addTextAnnotation) {
        addAnnotation(
          ImageAnnotation(
            kind: .text,
            text: language.annotationPlaceholder,
            normalizedRect: NormalizedCropRect(
              x: 0.3,
              y: 0.3,
              width: 0.4,
              height: 0.14
            )
          )
        )
      }
      Button(language.addRectangleAnnotation) {
        addAnnotation(
          ImageAnnotation(
            kind: .rectangle,
            normalizedRect: NormalizedCropRect(
              x: 0.3,
              y: 0.3,
              width: 0.4,
              height: 0.3
            )
          )
        )
      }
      Button(language.addArrowAnnotation) {
        addAnnotation(
          ImageAnnotation(
            kind: .arrow,
            normalizedRect: NormalizedCropRect(
              x: 0.25,
              y: 0.25,
              width: 0.5,
              height: 0.4
            )
          )
        )
      }

      if let annotation = selectedAnnotationBinding {
        Divider()
        annotationControls(annotation)
        Button(language.deleteAnnotation, role: .destructive) {
          let id = annotation.wrappedValue.id
          updateSnapshot { snapshot in
            snapshot.annotations.removeAll { $0.id == id }
          }
          selectedAnnotationID = nil
        }
      }
      if !editSnapshot.annotations.isEmpty {
        Button(language.clearAnnotations, role: .destructive) {
          updateSnapshot { $0.annotations.removeAll() }
          selectedAnnotationID = nil
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

      Picker(language.maskMode, selection: $maskOperation) {
        Label(language.maskPaint, systemImage: "paintbrush.fill")
          .tag(MaskStrokeOperation.paint)
        Label(language.maskErase, systemImage: "eraser.fill")
          .tag(MaskStrokeOperation.erase)
      }
      .pickerStyle(.segmented)

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

  @ViewBuilder
  private func annotationControls(_ annotation: Binding<ImageAnnotation>) -> some View {
    switch annotation.wrappedValue.kind {
    case .text:
      TextField(language.annotationText, text: annotation.text)
      Picker(language.annotationFont, selection: annotation.textStyle.fontName) {
        ForEach(["Helvetica", "Arial", "Avenir Next", "Georgia", "Menlo"], id: \.self) {
          Text($0).tag($0)
        }
      }
      HStack {
        Text(language.annotationFontSize)
        Slider(value: annotation.textStyle.fontSize, in: 8...96, step: 1)
        Text("\(Int(annotation.wrappedValue.textStyle.fontSize))")
          .monospacedDigit()
      }
      Toggle(language.annotationBold, isOn: annotation.textStyle.isBold)
      Toggle(language.annotationItalic, isOn: annotation.textStyle.isItalic)
      RGBAColorPicker(title: language.annotationColor, color: annotation.textStyle.color)
    case .rectangle:
      RGBAColorPicker(
        title: language.annotationStrokeColor,
        color: annotation.rectangleStyle.strokeColor
      )
      RGBAColorPicker(
        title: language.annotationFillColor,
        color: annotation.rectangleStyle.fillColor
      )
      lineWidthSlider(annotation.rectangleStyle.lineWidth)
      Picker(language.annotationLineStyle, selection: annotation.rectangleStyle.lineStyle) {
        ForEach(AnnotationLineStyle.allCases, id: \.self) { style in
          Text(language.annotationLineStyleName(style)).tag(style)
        }
      }
    case .arrow:
      RGBAColorPicker(title: language.annotationColor, color: annotation.arrowStyle.color)
      lineWidthSlider(annotation.arrowStyle.lineWidth)
      Picker(language.arrowDirection, selection: annotation.arrowStyle.direction) {
        ForEach(ArrowDirection.allCases, id: \.self) { direction in
          Text(language.arrowDirectionName(direction)).tag(direction)
        }
      }
    }
  }

  private func lineWidthSlider(_ width: Binding<Double>) -> some View {
    HStack {
      Text(language.annotationLineWidth)
      Slider(value: width, in: 1...16, step: 1)
      Text("\(Int(width.wrappedValue))")
        .monospacedDigit()
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
    editSession.update(mutate)
  }

  private func addAnnotation(_ annotation: ImageAnnotation) {
    updateSnapshot { $0.annotations.append(annotation) }
    selectedAnnotationID = annotation.id
  }

  private var selectedAnnotationBinding: Binding<ImageAnnotation>? {
    guard
      let selectedAnnotationID,
      editSnapshot.annotations.contains(where: { $0.id == selectedAnnotationID })
    else {
      return nil
    }
    return Binding(
      get: {
        editSnapshot.annotations.first(where: { $0.id == selectedAnnotationID })
          ?? ImageAnnotation(
            kind: .text,
            normalizedRect: NormalizedCropRect(
              x: 0.3,
              y: 0.3,
              width: 0.4,
              height: 0.14
            )
          )
      },
      set: { annotation in
        updateSnapshot { snapshot in
          guard
            let index = snapshot.annotations.firstIndex(where: {
              $0.id == selectedAnnotationID
            })
          else {
            return
          }
          snapshot.annotations[index] = annotation
        }
      }
    )
  }

  private func revertEdits() {
    editSession.revert()
    currentMaskStroke = nil
    selectedAnnotationID = nil
    exportMessage = nil
    isCropEditing = true
  }

  private func resetGeometry() {
    updateSnapshot {
      $0.cropRect = ImageEditSnapshot.defaultInitial.cropRect
      $0.quarterTurns = 0
      $0.flippedHorizontally = false
    }
    isCropEditing = true
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
