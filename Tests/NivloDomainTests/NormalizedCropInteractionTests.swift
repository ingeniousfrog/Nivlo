import CoreGraphics
import NivloDomain
import Testing

@Suite("Normalized crop interaction")
struct NormalizedCropInteractionTests {
  @Test("moves the crop frame using canvas-relative drag distance")
  func movesCropFrame() {
    let crop = NormalizedCropRect(x: 0.2, y: 0.25, width: 0.4, height: 0.5)

    let moved = crop.applying(
      handle: .move,
      translation: CGSize(width: 20, height: -10),
      canvasSize: CGSize(width: 200, height: 100)
    )

    #expect(abs(moved.x - 0.3) < 0.000_001)
    #expect(abs(moved.y - 0.15) < 0.000_001)
    #expect(moved.width == 0.4)
    #expect(moved.height == 0.5)
  }

  @Test("keeps a moved crop frame inside the image")
  func clampsMovedCropFrame() {
    let crop = NormalizedCropRect(x: 0.7, y: 0.7, width: 0.25, height: 0.25)

    let moved = crop.applying(
      handle: .move,
      translation: CGSize(width: 80, height: 80),
      canvasSize: CGSize(width: 100, height: 100)
    )

    #expect(moved == NormalizedCropRect(x: 0.75, y: 0.75, width: 0.25, height: 0.25))
  }

  @Test("resizes from the top-left handle without crossing minimum size")
  func resizesTopLeftHandle() {
    let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)

    let resized = crop.applying(
      handle: .topLeft,
      translation: CGSize(width: 80, height: 80),
      canvasSize: CGSize(width: 100, height: 100),
      minimumSize: 0.08
    )

    #expect(abs(resized.x - 0.62) < 0.000_001)
    #expect(abs(resized.y - 0.62) < 0.000_001)
    #expect(abs(resized.width - 0.08) < 0.000_001)
    #expect(abs(resized.height - 0.08) < 0.000_001)
  }

  @Test("ignores drag input when the canvas has no usable size")
  func ignoresInvalidCanvasSize() {
    let crop = NormalizedCropRect(x: 0.2, y: 0.2, width: 0.5, height: 0.5)

    let moved = crop.applying(
      handle: .move,
      translation: CGSize(width: 20, height: 20),
      canvasSize: .zero
    )

    #expect(moved == crop)
  }
}
