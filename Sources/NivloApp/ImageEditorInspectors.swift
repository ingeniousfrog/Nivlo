import NivloDomain
import SwiftUI

struct ImageGeometryInspector: View {
  let language: NivloLanguage
  @Binding var cropRect: NormalizedCropRect
  @Binding var quarterTurns: Int
  @Binding var flippedHorizontally: Bool
  @Binding var isCropEditing: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text(isCropEditing ? language.editorGeometryHint : language.cropAppliedHint)
        .font(.caption)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      let crop = cropRect.clamped()
      Text(
        "\(language.cropSizeLabel): \(Int(crop.width * 100))% × \(Int(crop.height * 100))%"
      )
      .font(.caption.monospacedDigit())
      .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        Button {
          quarterTurns = normalizedQuarterTurns(quarterTurns - 1)
        } label: {
          Label(language.rotateLeft, systemImage: "rotate.left")
        }
        Button {
          quarterTurns = normalizedQuarterTurns(quarterTurns + 1)
        } label: {
          Label(language.rotateRight, systemImage: "rotate.right")
        }
      }
      Button {
        flippedHorizontally.toggle()
      } label: {
        Label(
          language.flipHorizontal,
          systemImage: "arrow.left.and.right.righttriangle.left.righttriangle.right"
        )
      }
      if !isCropEditing, !cropRect.isEffectivelyFull {
        Button(language.adjustCrop) {
          isCropEditing = true
        }
      }
      HStack(spacing: 8) {
        Button(language.applyCrop) {
          isCropEditing = false
        }
        .buttonStyle(.borderedProminent)
        .disabled(cropRect.isEffectivelyFull || !isCropEditing)
        Button(language.reset) {
          cropRect = .full
          quarterTurns = 0
          flippedHorizontally = false
          isCropEditing = true
        }
        .buttonStyle(.bordered)
      }
    }
  }

  private func normalizedQuarterTurns(_ value: Int) -> Int {
    (value % 4 + 4) % 4
  }
}

struct ImageAnnotationInspector: View {
  let language: NivloLanguage
  @Binding var annotations: [ImageAnnotation]
  @Binding var selectedAnnotationID: UUID?

  var body: some View {
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
          annotations.removeAll { $0.id == id }
          selectedAnnotationID = nil
        }
      }
      if !annotations.isEmpty {
        Button(language.clearAnnotations, role: .destructive) {
          annotations.removeAll()
          selectedAnnotationID = nil
        }
      }
    }
  }

  @ViewBuilder
  private func annotationControls(
    _ annotation: Binding<ImageAnnotation>
  ) -> some View {
    switch annotation.wrappedValue.kind {
    case .text:
      LabeledContent(language.annotationText) {
        TextField(language.annotationPlaceholder, text: annotation.text)
          .textFieldStyle(.roundedBorder)
      }
      Picker(language.annotationFont, selection: annotation.textStyle.fontName) {
        ForEach(
          ["Helvetica", "Arial", "Avenir Next", "Georgia", "Menlo"],
          id: \.self
        ) {
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
      RGBAColorPicker(
        title: language.annotationColor,
        color: annotation.textStyle.color,
        cancelTitle: language.cancel,
        confirmTitle: language.confirm
      )
    case .rectangle:
      RGBAColorPicker(
        title: language.annotationStrokeColor,
        color: annotation.rectangleStyle.strokeColor,
        cancelTitle: language.cancel,
        confirmTitle: language.confirm
      )
      RGBAColorPicker(
        title: language.annotationFillColor,
        color: annotation.rectangleStyle.fillColor,
        cancelTitle: language.cancel,
        confirmTitle: language.confirm
      )
      lineWidthSlider(annotation.rectangleStyle.lineWidth)
      Picker(
        language.annotationLineStyle,
        selection: annotation.rectangleStyle.lineStyle
      ) {
        ForEach(AnnotationLineStyle.allCases, id: \.self) { style in
          Text(language.annotationLineStyleName(style)).tag(style)
        }
      }
    case .arrow:
      RGBAColorPicker(
        title: language.annotationColor,
        color: annotation.arrowStyle.color,
        cancelTitle: language.cancel,
        confirmTitle: language.confirm
      )
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

  private func addAnnotation(_ annotation: ImageAnnotation) {
    annotations.append(annotation)
    selectedAnnotationID = annotation.id
  }

  private var selectedAnnotationBinding: Binding<ImageAnnotation>? {
    guard
      let selectedAnnotationID,
      annotations.contains(where: { $0.id == selectedAnnotationID })
    else {
      return nil
    }
    return Binding(
      get: {
        annotations.first(where: { $0.id == selectedAnnotationID })
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
        guard
          let index = annotations.firstIndex(where: {
            $0.id == selectedAnnotationID
          })
        else {
          return
        }
        annotations[index] = annotation
      }
    )
  }
}

struct ImageMaskInspector: View {
  let language: NivloLanguage
  @Binding var maskStrokes: [MaskStroke]
  @Binding var localAdjustments: [LocalImageAdjustment]
  @Binding var currentMaskStroke: MaskStroke?
  @Binding var brushRadius: Double
  @Binding var maskOperation: MaskStrokeOperation
  @Binding var localAdjustmentSettings: ImageAdjustmentSettings

  var body: some View {
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

      Text("\(language.maskStrokeCount): \(maskStrokes.count)")
        .font(.caption)
        .foregroundStyle(.secondary)

      if !maskStrokes.isEmpty {
        Divider()
        Text(language.localAdjustment)
          .font(.subheadline.weight(.semibold))
        adjustmentSlider(
          language.adjustExposure,
          keyPath: \.exposure,
          range: -2...2
        )
        adjustmentSlider(
          language.adjustClarity,
          keyPath: \.clarity,
          range: -1...1
        )
        adjustmentSlider(
          language.adjustSaturation,
          keyPath: \.saturation,
          range: -1...1
        )
        Button(language.addLocalAdjustment) {
          localAdjustments.append(
            LocalImageAdjustment(
              name: "\(language.localAdjustment) \(localAdjustments.count + 1)",
              settings: localAdjustmentSettings,
              maskStrokes: maskStrokes
            )
          )
          maskStrokes = []
          localAdjustmentSettings = .neutral
        }
        .buttonStyle(.borderedProminent)
        Button(language.clearMask, role: .destructive) {
          maskStrokes.removeAll()
          currentMaskStroke = nil
        }
      }
      if !localAdjustments.isEmpty {
        Divider()
        ForEach(localAdjustments) { adjustment in
          HStack {
            Toggle(
              adjustment.name,
              isOn: visibilityBinding(adjustment.id)
            )
            Button(role: .destructive) {
              localAdjustments.removeAll { $0.id == adjustment.id }
            } label: {
              Image(systemName: "trash")
            }
          }
        }
      }
    }
  }

  private func adjustmentSlider(
    _ title: String,
    keyPath: WritableKeyPath<ImageAdjustmentSettings, Double>,
    range: ClosedRange<Double>
  ) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(title)
        .font(.caption)
      Slider(
        value: Binding(
          get: { localAdjustmentSettings[keyPath: keyPath] },
          set: { localAdjustmentSettings[keyPath: keyPath] = $0 }
        ),
        in: range
      )
    }
  }

  private func visibilityBinding(_ id: UUID) -> Binding<Bool> {
    Binding(
      get: {
        localAdjustments.first(where: { $0.id == id })?.isVisible ?? false
      },
      set: { value in
        guard
          let index = localAdjustments.firstIndex(where: { $0.id == id })
        else {
          return
        }
        localAdjustments[index].isVisible = value
      }
    )
  }
}
