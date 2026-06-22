import CoreGraphics
import NivloDomain
import Testing

@Suite("Image annotations")
struct ImageAnnotationTests {
  @Test("new text annotations expose editable typography defaults")
  func textAnnotationDefaults() {
    let annotation = ImageAnnotation(
      kind: .text,
      text: "Note",
      normalizedRect: NormalizedCropRect(x: 0.1, y: 0.1, width: 0.3, height: 0.1)
    )

    #expect(annotation.textStyle.fontName == "Helvetica")
    #expect(annotation.textStyle.fontSize == 28)
    #expect(annotation.textStyle.color == .white)
    #expect(annotation.textStyle.isBold)
    #expect(!annotation.textStyle.isItalic)
  }

  @Test("rectangle annotations support fill and dashed strokes")
  func rectangleStyle() {
    let style = RectangleAnnotationStyle(
      strokeColor: .red,
      fillColor: RGBAColor(red: 0.2, green: 0.4, blue: 0.8, alpha: 0.25),
      lineWidth: 6,
      lineStyle: .dashed
    )
    let annotation = ImageAnnotation(
      kind: .rectangle,
      normalizedRect: NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3),
      rectangleStyle: style
    )

    #expect(annotation.rectangleStyle == style)
  }

  @Test("arrow annotations preserve direction and appearance")
  func arrowStyle() {
    let style = ArrowAnnotationStyle(
      color: .blue,
      lineWidth: 8,
      direction: .both
    )
    let annotation = ImageAnnotation(
      kind: .arrow,
      normalizedRect: NormalizedCropRect(x: 0.15, y: 0.2, width: 0.6, height: 0.4),
      arrowStyle: style
    )

    #expect(annotation.arrowStyle == style)
  }

  @Test("annotation frames move and resize with all crop handles")
  func annotationFrameInteraction() {
    let frame = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3)

    let moved = frame.applying(
      handle: .move,
      translation: CGSize(width: 20, height: 10),
      canvasSize: CGSize(width: 200, height: 100)
    )
    let resized = frame.applying(
      handle: .bottomRight,
      translation: CGSize(width: 40, height: 20),
      canvasSize: CGSize(width: 200, height: 100)
    )

    #expect(abs(moved.x - 0.3) < 0.000_001)
    #expect(abs(moved.y - 0.3) < 0.000_001)
    #expect(abs(resized.width - 0.6) < 0.000_001)
    #expect(abs(resized.height - 0.5) < 0.000_001)
  }
}
