import CoreGraphics
import Foundation
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

  @Test("arrow annotations store independent start and end points")
  func arrowEndpoints() {
    let annotation = ImageAnnotation(
      kind: .arrow,
      normalizedRect: NormalizedCropRect(x: 0.1, y: 0.2, width: 0.7, height: 0.5),
      arrowStart: NormalizedPoint(x: 0.15, y: 0.75),
      arrowEnd: NormalizedPoint(x: 0.85, y: 0.25)
    )

    #expect(annotation.arrowStart == NormalizedPoint(x: 0.15, y: 0.75))
    #expect(annotation.arrowEnd == NormalizedPoint(x: 0.85, y: 0.25))
  }

  @Test("annotations store a center rotation angle")
  func rotationAngle() {
    let annotation = ImageAnnotation(
      kind: .rectangle,
      normalizedRect: NormalizedCropRect(x: 0.2, y: 0.2, width: 0.4, height: 0.3),
      rotationDegrees: 37
    )

    #expect(annotation.rotationDegrees == 37)
  }

  @Test("moving an arrow translates both endpoints without changing its vector")
  func moveArrowEndpoints() {
    let start = NormalizedPoint(x: 0.2, y: 0.7)
    let end = NormalizedPoint(x: 0.6, y: 0.3)

    let moved = ArrowGeometry.moving(
      start: start,
      end: end,
      translation: CGSize(width: 20, height: -10),
      canvasSize: CGSize(width: 200, height: 100)
    )

    #expect(abs(moved.start.x - 0.3) < 0.000_001)
    #expect(abs(moved.start.y - 0.6) < 0.000_001)
    #expect(abs(moved.end.x - 0.7) < 0.000_001)
    #expect(abs(moved.end.y - 0.2) < 0.000_001)
  }

  @Test("rotation angle is derived around an annotation center")
  func angleAroundCenter() {
    let angle = AnnotationGeometry.rotationDegrees(
      center: CGPoint(x: 100, y: 100),
      handle: CGPoint(x: 100, y: 40)
    )

    #expect(abs(angle) < 0.000_001)
  }

  @Test("screen drag translation maps into the rotated annotation coordinate space")
  func rotatedLocalTranslation() {
    let local = AnnotationGeometry.localTranslation(
      CGSize(width: 20, height: 0),
      rotationDegrees: 90
    )

    #expect(abs(local.width) < 0.000_001)
    #expect(abs(local.height + 20) < 0.000_001)
  }

  @Test("older annotations decode with default rotation and arrow endpoints")
  func decodesLegacyAnnotation() throws {
    let original = ImageAnnotation(
      kind: .arrow,
      normalizedRect: NormalizedCropRect(x: 0.1, y: 0.2, width: 0.6, height: 0.5)
    )
    let encoded = try JSONEncoder().encode(original)
    var object = try #require(
      JSONSerialization.jsonObject(with: encoded) as? [String: Any]
    )
    object.removeValue(forKey: "rotationDegrees")
    object.removeValue(forKey: "arrowStart")
    object.removeValue(forKey: "arrowEnd")

    let legacyData = try JSONSerialization.data(withJSONObject: object)
    let decoded = try JSONDecoder().decode(ImageAnnotation.self, from: legacyData)

    #expect(decoded.rotationDegrees == 0)
    #expect(decoded.arrowStart == NormalizedPoint(x: 0.1, y: 0.7))
    #expect(decoded.arrowEnd == NormalizedPoint(x: 0.7, y: 0.2))
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
