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
  @State private var cropRect = NormalizedCropRect.full
  @State private var quarterTurns = 0
  @State private var isFlippedHorizontally = false
  @State private var adjustments = ImageAdjustmentSettings.neutral
  @State private var annotations: [ImageAnnotation] = []
  @State private var maskStrokes: [MaskStroke] = []
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

  private let pipeline = ImageEditPipeline()
  private let sidebarWidth: CGFloat = 220
  private let inspectorWidth: CGFloat = 320

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
    .frame(minWidth: 1_120, minHeight: 760)
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
        selectedTab = .export
        exportEditedCopy()
      } label: {
        Label(language.saveEditedCopy, systemImage: "square.and.arrow.up")
      }
      .buttonStyle(.borderedProminent)
      .disabled(!canEdit || isExporting || !toolsReady)
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
      ForEach(ImageEditorTab.allCases) { tab in
        Label(tab.title(language: language), systemImage: tab.icon)
          .tag(tab)
      }
    }
    .listStyle(.sidebar)
    .frame(width: sidebarWidth)
  }

  private var editorCanvas: some View {
    GeometryReader { proxy in
      ZStack {
        Color(nsColor: .underPageBackgroundColor)
        if canEdit {
          AssetImageView(
            asset: asset,
            enrichment: nil,
            maxPixelSize: 1_800,
            contentMode: .fit
          )
          .rotationEffect(.degrees(Double(quarterTurns * 90)))
          .scaleEffect(x: isFlippedHorizontally ? -1 : 1, y: 1)
          .overlay {
            if selectedTab == .geometry {
              CropOverlayView(cropRect: $cropRect)
            }
          }
          .padding(24)
          .frame(maxWidth: proxy.size.width, maxHeight: proxy.size.height)
          .animation(.snappy, value: quarterTurns)
          .animation(.snappy, value: isFlippedHorizontally)
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
        ProgressView()
          .controlSize(.small)
        Text(language.exportingImage)
      } else if let exportMessage {
        Text(exportMessage)
      } else {
        Text(language.editorCanvasHint)
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

  private var geometryControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      Text(language.editorGeometryHint)
        .font(.caption)
        .foregroundStyle(.secondary)
      HStack(spacing: 8) {
        Button { quarterTurns = normalizedQuarterTurns(quarterTurns - 1) } label: {
          Label(language.rotateLeft, systemImage: "rotate.left")
        }
        Button { quarterTurns = normalizedQuarterTurns(quarterTurns + 1) } label: {
          Label(language.rotateRight, systemImage: "rotate.right")
        }
      }
      Button { isFlippedHorizontally.toggle() } label: {
        Label(language.flipHorizontal, systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right")
      }
      Button(language.reset) {
        cropRect = .full
        quarterTurns = 0
        isFlippedHorizontally = false
      }
    }
  }

  private var adjustControls: some View {
    VStack(alignment: .leading, spacing: 14) {
      sliderRow(language.adjustExposure, value: $adjustments.exposure, range: -1...1)
      sliderRow(language.adjustContrast, value: $adjustments.contrast, range: -0.5...0.5)
      sliderRow(language.adjustSaturation, value: $adjustments.saturation, range: -0.5...0.5)
      sliderRow(language.adjustWarmth, value: $adjustments.warmth, range: -1...1)
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
      Text("\(language.annotationCount): \(annotations.count)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private var maskControls: some View {
    VStack(alignment: .leading, spacing: 12) {
      ForEach($layers) { $layer in
        Toggle(layerTitle(layer.kind), isOn: $layer.isVisible)
      }
      Button(language.addMaskStroke) {
        maskStrokes.append(
          MaskStroke(
            normalizedRect: NormalizedCropRect(x: 0.35, y: 0.35, width: 0.2, height: 0.2)
          )
        )
      }
      if !maskStrokes.isEmpty {
        Button(language.clearMask, role: .destructive) {
          maskStrokes.removeAll()
        }
      }
      Text("\(language.maskStrokeCount): \(maskStrokes.count)")
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func layerTitle(_ kind: EditorLayerKind) -> String {
    switch kind {
    case .background: language.layerBackground
    case .adjustments: language.layerAdjustments
    case .annotations: language.layerAnnotations
    case .mask: language.layerMask
    }
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

  private func exportEditedCopy() {
    let panel = NSSavePanel()
    panel.title = language.saveEditedCopy
    panel.nameFieldStringValue =
      "\(asset.url.deletingPathExtension().lastPathComponent)-edited.\(outputFormat.rawValue)"
    panel.allowedContentTypes = [uti(for: outputFormat)]
    guard panel.runModal() == .OK, let outputURL = panel.url else {
      return
    }
    guard outputURL.standardizedFileURL != asset.url.standardizedFileURL else {
      exportMessage = language.originalFileProtected
      return
    }

    let request = ImageEditRequest(
      sourceURL: asset.url,
      outputURL: outputURL,
      cropRect: cropRect.clamped(),
      quarterTurns: quarterTurns,
      flippedHorizontally: isFlippedHorizontally,
      adjustments: adjustments,
      annotations: annotations,
      maskStrokes: maskStrokes,
      layers: layers,
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

private struct CropOverlayView: View {
  @Binding var cropRect: NormalizedCropRect

  var body: some View {
    GeometryReader { proxy in
      let rect = CGRect(
        x: cropRect.x * proxy.size.width,
        y: cropRect.y * proxy.size.height,
        width: cropRect.width * proxy.size.width,
        height: cropRect.height * proxy.size.height
      )
      ZStack {
        Rectangle()
          .strokeBorder(.yellow, lineWidth: 2)
          .background(.yellow.opacity(0.08))
          .frame(width: rect.width, height: rect.height)
          .position(x: rect.midX, y: rect.midY)
          .gesture(
            DragGesture()
              .onChanged { value in
                let nx = min(max(0, value.location.x / proxy.size.width - cropRect.width / 2), 1 - cropRect.width)
                let ny = min(max(0, value.location.y / proxy.size.height - cropRect.height / 2), 1 - cropRect.height)
                cropRect.x = nx
                cropRect.y = ny
              }
          )
      }
    }
  }
}
