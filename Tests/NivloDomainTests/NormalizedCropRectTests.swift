import CoreGraphics
import NivloDomain
import Testing

@Suite("Normalized crop rect")
struct NormalizedCropRectTests {
  @Test("maps top-left normalized crop into Core Image coordinates")
  func ciCropCGRectUsesBottomLeftOrigin() {
    let crop = NormalizedCropRect(x: 0.1, y: 0.2, width: 0.5, height: 0.3)
    let rect = crop.ciCropCGRect(imageWidth: 1_000, imageHeight: 800)

    #expect(rect.origin.x == 100)
    #expect(rect.size.width == 500)
    #expect(rect.size.height == 240)
    #expect(rect.origin.y == 400)
  }

  @Test("detects effectively full crop")
  func effectivelyFullCrop() {
    #expect(NormalizedCropRect.full.isEffectivelyFull)
    #expect(!NormalizedCropRect(x: 0.05, y: 0.05, width: 0.9, height: 0.9).isEffectivelyFull)
  }
}
