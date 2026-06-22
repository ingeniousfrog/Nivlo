import NivloDomain
import Testing

@Suite("Mask strokes")
struct MaskStrokeTests {
  @Test("mask strokes distinguish painting from erasing")
  func strokeOperation() {
    let paint = MaskStroke(operation: .paint)
    let erase = MaskStroke(operation: .erase)

    #expect(paint.operation == .paint)
    #expect(erase.operation == .erase)
    #expect(paint != erase)
  }
}
