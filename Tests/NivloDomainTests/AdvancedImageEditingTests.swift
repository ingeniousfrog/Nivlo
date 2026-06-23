import Foundation
import NivloDomain
import Testing

@Suite("Advanced image editing")
struct AdvancedImageEditingTests {
  @Test("undo and redo preserve immutable edit snapshots")
  func undoRedo() {
    let initial = ImageEditSnapshot()
    var session = ImageEditSession(initialSnapshot: initial)

    session.update { $0.adjustments.exposure = 0.4 }
    let exposed = session.currentSnapshot
    session.update { $0.adjustments.gamma = 1.4 }

    #expect(session.canUndo)
    session.undo()
    #expect(session.currentSnapshot == exposed)
    #expect(session.canRedo)
    session.redo()
    #expect(session.currentSnapshot.adjustments.gamma == 1.4)
    #expect(initial.adjustments == .neutral)
  }

  @Test("levels and curves normalize invalid input")
  func normalizedToneControls() {
    let levels = ImageLevels(blackPoint: 0.8, whitePoint: 0.2, gamma: 0)
    let curve = ToneCurve(points: [
      ToneCurvePoint(x: 1, y: 0.9),
      ToneCurvePoint(x: 0.5, y: 0.7),
      ToneCurvePoint(x: 0, y: 0.1),
    ])

    #expect(levels.blackPoint < levels.whitePoint)
    #expect(levels.gamma >= 0.1)
    #expect(curve.value(at: 0.25) == 0.4)
    #expect(curve.points.map(\.x) == [0, 0.5, 1])
  }

  @Test("advanced settings and local adjustments round trip")
  func codableRoundTrip() throws {
    let snapshot = ImageEditSnapshot(
      adjustments: ImageAdjustmentSettings(
        exposure: 0.2,
        contrast: 0.1,
        saturation: 0.3,
        warmth: 0.2,
        tint: -0.1,
        highlights: -0.2,
        shadows: 0.4,
        clarity: 0.25,
        vibrance: 0.3,
        sharpness: 0.5,
        noiseReduction: 0.2,
        vignette: 0.3,
        levels: [
          .rgb: ImageLevels(blackPoint: 0.05, whitePoint: 0.95, gamma: 1.1)
        ],
        curves: [
          .rgb: ToneCurve(points: [
            ToneCurvePoint(x: 0, y: 0),
            ToneCurvePoint(x: 0.5, y: 0.6),
            ToneCurvePoint(x: 1, y: 1),
          ])
        ],
        colorBands: [
          .blue: HSLBandAdjustment(hue: 0.1, saturation: 0.2, luminance: -0.1)
        ]
      ),
      localAdjustments: [
        LocalImageAdjustment(
          name: "Face",
          settings: ImageAdjustmentSettings(exposure: 0.3),
          maskStrokes: [
            MaskStroke(points: [MaskBrushPoint(x: 0.5, y: 0.5)])
          ]
        )
      ]
    )

    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(ImageEditSnapshot.self, from: data)

    #expect(decoded == snapshot)
  }

  @Test("adjustments report when the full render engine is needed")
  func fullRenderRequirement() {
    #expect(!ImageAdjustmentSettings.neutral.requiresFullRenderPreview)
    #expect(!ImageAdjustmentSettings(exposure: 0.4, contrast: 0.1).requiresFullRenderPreview)
    #expect(ImageAdjustmentSettings(tint: 0.2).requiresFullRenderPreview)
    #expect(
      ImageAdjustmentSettings(
        curves: [
          .rgb: ToneCurve(points: [
            ToneCurvePoint(x: 0, y: 0),
            ToneCurvePoint(x: 0.5, y: 0.7),
            ToneCurvePoint(x: 1, y: 1),
          ])
        ]
      ).requiresFullRenderPreview
    )
  }

  @Test("decoded tone controls normalize untrusted values")
  func decodedToneControlsAreNormalized() throws {
    let levels = try JSONDecoder().decode(
      ImageLevels.self,
      from: Data(#"{"blackPoint":2,"whitePoint":-1,"gamma":0}"#.utf8)
    )
    let curve = try JSONDecoder().decode(
      ToneCurve.self,
      from: Data(#"{"points":[{"x":2,"y":-1},{"x":-1,"y":2}]}"#.utf8)
    )
    let colorBand = try JSONDecoder().decode(
      HSLBandAdjustment.self,
      from: Data(#"{"hue":2,"saturation":-2,"luminance":3}"#.utf8)
    )

    #expect(levels.blackPoint < levels.whitePoint)
    #expect(levels.gamma == 0.1)
    #expect(curve.points.map(\.x) == [0, 1])
    #expect(curve.points.map(\.y) == [1, 0])
    #expect(colorBand == HSLBandAdjustment(hue: 1, saturation: -1, luminance: 1))
  }

  @Test("built in presets are reusable immutable values")
  func presets() {
    let vivid = ImageAdjustmentPreset.builtIn.first { $0.id == "vivid" }
    let web = ImageExportPreset.builtIn.first { $0.id == "web" }

    #expect(vivid?.settings.vibrance == 0.35)
    #expect(web?.format == .webp)
    #expect(web?.quality == 82)
  }
}
