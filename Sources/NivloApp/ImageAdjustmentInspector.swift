import NivloDomain
import SwiftUI

private enum AdjustmentInspectorSection: String, CaseIterable, Identifiable {
  case basic
  case levels
  case curves
  case hsl

  var id: String { rawValue }

  func title(language: NivloLanguage) -> String {
    switch self {
    case .basic:
      language.basicAdjustments
    case .levels:
      language.levels
    case .curves:
      language.curves
    case .hsl:
      language.shortColorMixer
    }
  }
}

struct ImageAdjustmentInspector: View {
  let language: NivloLanguage
  @Binding var settings: ImageAdjustmentSettings
  let requiresFullRenderPreview: Bool
  let isRenderingPreview: Bool
  let isRenderedPreviewPresented: Bool
  let isRenderPreviewDisabled: Bool
  let presets: [ImageAdjustmentPreset]
  @Binding var selectedPresetID: String
  @Binding var presetName: String
  let onSavePreset: () -> Void
  let onRenderPreview: () -> Void

  @State private var levelChannel: ImageColorChannel = .rgb
  @State private var curveChannel: ImageColorChannel = .rgb
  @State private var colorBand: HSLColorBand = .red
  @State private var isPresetExpanded = false
  @State private var selectedSection: AdjustmentInspectorSection = .basic

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      renderPreviewBar

      DisclosureGroup(language.adjustmentPreset, isExpanded: $isPresetExpanded) {
        VStack(alignment: .leading, spacing: 8) {
          Picker(language.adjustmentPreset, selection: $selectedPresetID) {
            Text(language.custom).tag("")
            ForEach(presets) { preset in
              Text(preset.name).tag(preset.id)
            }
          }
          .onChange(of: selectedPresetID) { _, id in
            guard let preset = presets.first(where: { $0.id == id }) else {
              return
            }
            settings = preset.settings
          }
          HStack {
            TextField(language.presetName, text: $presetName)
            Button(language.savePreset, action: onSavePreset)
              .disabled(presetName.trimmingCharacters(in: .whitespaces).isEmpty)
          }
        }
      }
      .font(.caption)
      .padding(.vertical, 2)

      sectionPicker
      sectionCard
    }
  }

  private var renderPreviewBar: some View {
    HStack(spacing: 10) {
      Text(
        requiresFullRenderPreview
          ? language.fullRenderPreviewHint : language.renderPreviewControlHint
      )
      .font(.caption)
      .foregroundStyle(.secondary)
      .lineLimit(1)

      Spacer(minLength: 8)

      Button {
        onRenderPreview()
      } label: {
        if isRenderingPreview {
          ProgressView()
            .controlSize(.small)
        } else {
          Text(isRenderedPreviewPresented ? language.exitPreview : language.previewChanges)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
      .disabled(isRenderingPreview || isRenderPreviewDisabled)
      .help(isRenderedPreviewPresented ? language.exitPreview : language.renderedPreview)
    }
    .padding(.vertical, 2)
  }

  private var sectionPicker: some View {
    Picker(language.adjustmentSection, selection: $selectedSection) {
      ForEach(AdjustmentInspectorSection.allCases) { section in
        Text(section.title(language: language)).tag(section)
      }
    }
    .pickerStyle(.segmented)
    .controlSize(.small)
  }

  private var sectionCard: some View {
    VStack(alignment: .leading, spacing: 10) {
      switch selectedSection {
      case .basic:
        basicControls
      case .levels:
        levelsControls
      case .curves:
        curvesControls
      case .hsl:
        hslControls
      }
    }
    .padding(10)
    .background(
      Color(nsColor: .controlBackgroundColor).opacity(0.75),
      in: RoundedRectangle(cornerRadius: 12)
    )
  }

  private var basicControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      slider(language.adjustExposure, value: $settings.exposure, range: -2...2)
      slider(language.adjustContrast, value: $settings.contrast, range: -0.5...0.5)
      slider(language.adjustSaturation, value: $settings.saturation, range: -1...1)
      slider(language.adjustWarmth, value: $settings.warmth, range: -1...1)
      slider(language.adjustTint, value: $settings.tint, range: -1...1)
      slider(language.adjustHighlights, value: $settings.highlights, range: -1...1)
      slider(language.adjustShadows, value: $settings.shadows, range: -1...1)
      slider(language.adjustClarity, value: $settings.clarity, range: -1...1)
      slider(language.adjustVibrance, value: $settings.vibrance, range: -1...1)
      slider(language.adjustSharpness, value: $settings.sharpness, range: 0...1)
      slider(language.adjustNoiseReduction, value: $settings.noiseReduction, range: 0...1)
      slider(language.adjustVignette, value: $settings.vignette, range: 0...1)
    }
  }

  private var levelsControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      channelPicker(selection: $levelChannel)
      slider(
        language.blackPoint,
        value: levelBinding(\.blackPoint),
        range: 0...0.95
      )
      slider(
        language.whitePoint,
        value: levelBinding(\.whitePoint),
        range: 0.05...1
      )
      slider(
        language.gamma,
        value: levelBinding(\.gamma),
        range: 0.1...3
      )
    }
  }

  private var curvesControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      channelPicker(selection: $curveChannel)
      CurveEditor(curve: curveBinding)
        .frame(height: 132)
    }
  }

  private var hslControls: some View {
    VStack(alignment: .leading, spacing: 10) {
      Picker(language.colorBand, selection: $colorBand) {
        ForEach(HSLColorBand.allCases, id: \.self) {
          Text($0.rawValue.capitalized).tag($0)
        }
      }
      .pickerStyle(.menu)
      .controlSize(.small)
      slider(language.hue, value: colorBandBinding(\.hue), range: -1...1)
      slider(
        language.adjustSaturation,
        value: colorBandBinding(\.saturation),
        range: -1...1
      )
      slider(
        language.luminance,
        value: colorBandBinding(\.luminance),
        range: -1...1
      )
    }
  }

  private func channelPicker(
    selection: Binding<ImageColorChannel>
  ) -> some View {
    Picker(language.channel, selection: selection) {
      ForEach(ImageColorChannel.allCases, id: \.self) {
        Text($0.rawValue.uppercased()).tag($0)
      }
    }
    .pickerStyle(.segmented)
    .controlSize(.small)
  }

  private func slider(
    _ title: String,
    value: Binding<Double>,
    range: ClosedRange<Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 3) {
      HStack {
        Text(title)
          .font(.caption)
        Spacer()
        Text(value.wrappedValue.formatted(.number.precision(.fractionLength(2))))
          .font(.caption.monospacedDigit())
          .foregroundStyle(.secondary)
      }
      Slider(value: value, in: range)
    }
  }

  private func levelBinding(
    _ keyPath: WritableKeyPath<ImageLevels, Double>
  ) -> Binding<Double> {
    Binding(
      get: {
        (settings.levels[levelChannel] ?? .neutral)[keyPath: keyPath]
      },
      set: { value in
        var levels = settings.levels[levelChannel] ?? .neutral
        levels[keyPath: keyPath] = value
        settings.levels[levelChannel] = ImageLevels(
          blackPoint: levels.blackPoint,
          whitePoint: levels.whitePoint,
          gamma: levels.gamma
        )
      }
    )
  }

  private var curveBinding: Binding<ToneCurve> {
    Binding(
      get: { settings.curves[curveChannel] ?? .identity },
      set: { settings.curves[curveChannel] = $0 }
    )
  }

  private func colorBandBinding(
    _ keyPath: WritableKeyPath<HSLBandAdjustment, Double>
  ) -> Binding<Double> {
    Binding(
      get: {
        (settings.colorBands[colorBand] ?? .neutral)[keyPath: keyPath]
      },
      set: { value in
        var adjustment = settings.colorBands[colorBand] ?? .neutral
        adjustment[keyPath: keyPath] = value
        settings.colorBands[colorBand] = HSLBandAdjustment(
          hue: adjustment.hue,
          saturation: adjustment.saturation,
          luminance: adjustment.luminance
        )
      }
    )
  }
}

private struct CurveEditor: View {
  @Binding var curve: ToneCurve
  @State private var activeIndex: Int?

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        Canvas { context, size in
          var grid = Path()
          for fraction in [0.25, 0.5, 0.75] {
            grid.move(to: CGPoint(x: size.width * fraction, y: 0))
            grid.addLine(to: CGPoint(x: size.width * fraction, y: size.height))
            grid.move(to: CGPoint(x: 0, y: size.height * fraction))
            grid.addLine(to: CGPoint(x: size.width, y: size.height * fraction))
          }
          context.stroke(grid, with: .color(.secondary.opacity(0.25)))

          var path = Path()
          for xIndex in 0...128 {
            let x = Double(xIndex) / 128
            let point = CGPoint(
              x: x * size.width,
              y: (1 - curve.value(at: x)) * size.height
            )
            if xIndex == 0 {
              path.move(to: point)
            } else {
              path.addLine(to: point)
            }
          }
          context.stroke(path, with: .color(.accentColor), lineWidth: 2)
        }
        ForEach(Array(curve.points.enumerated()), id: \.offset) { _, point in
          Circle()
            .fill(Color.accentColor)
            .overlay(Circle().stroke(.white, lineWidth: 1))
            .frame(width: 12, height: 12)
            .position(
              x: point.x * proxy.size.width,
              y: (1 - point.y) * proxy.size.height
            )
        }
        Color.clear
          .contentShape(Rectangle())
          .gesture(curveGesture(size: proxy.size))
      }
    }
    .background(.black.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
  }

  private func curveGesture(size: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        let point = ToneCurvePoint(
          x: Double(min(max(value.location.x / max(size.width, 1), 0), 1)),
          y: Double(1 - min(max(value.location.y / max(size.height, 1), 0), 1))
        )
        var points = curve.points
        if activeIndex == nil {
          activeIndex = nearestPointIndex(to: point, in: points)
          if activeIndex == nil, points.count < 8 {
            points.append(point)
            points.sort { $0.x < $1.x }
            activeIndex = points.firstIndex(of: point)
          }
        }
        guard let activeIndex, points.indices.contains(activeIndex) else {
          return
        }
        let isEndpoint = activeIndex == 0 || activeIndex == points.count - 1
        points[activeIndex] = ToneCurvePoint(
          x: isEndpoint ? points[activeIndex].x : point.x,
          y: point.y
        )
        curve = ToneCurve(points: points)
      }
      .onEnded { _ in activeIndex = nil }
  }

  private func nearestPointIndex(
    to point: ToneCurvePoint,
    in points: [ToneCurvePoint]
  ) -> Int? {
    points.enumerated()
      .map { index, candidate in
        (
          index,
          hypot(candidate.x - point.x, candidate.y - point.y)
        )
      }
      .filter { $0.1 < 0.12 }
      .min { $0.1 < $1.1 }?
      .0
  }
}
