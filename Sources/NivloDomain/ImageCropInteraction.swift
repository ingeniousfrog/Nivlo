import CoreGraphics

public enum NormalizedCropHandle: Sendable, Hashable {
  case move
  case topLeft
  case top
  case topRight
  case right
  case bottomRight
  case bottom
  case bottomLeft
  case left
}

extension NormalizedCropRect {
  public func applying(
    handle: NormalizedCropHandle,
    translation: CGSize,
    canvasSize: CGSize,
    minimumSize: Double = 0.05
  ) -> NormalizedCropRect {
    guard
      canvasSize.width.isFinite,
      canvasSize.height.isFinite,
      canvasSize.width > 0,
      canvasSize.height > 0
    else {
      return self
    }

    let start = clamped()
    let dx = Double(translation.width / canvasSize.width)
    let dy = Double(translation.height / canvasSize.height)
    let minimum = min(max(minimumSize, 0.01), 1)

    if handle == .move {
      return NormalizedCropRect(
        x: min(max(0, start.x + dx), 1 - start.width),
        y: min(max(0, start.y + dy), 1 - start.height),
        width: start.width,
        height: start.height
      )
    }

    let startRight = start.x + start.width
    let startBottom = start.y + start.height
    let movesLeft = handle == .left || handle == .topLeft || handle == .bottomLeft
    let movesRight = handle == .right || handle == .topRight || handle == .bottomRight
    let movesTop = handle == .top || handle == .topLeft || handle == .topRight
    let movesBottom = handle == .bottom || handle == .bottomLeft || handle == .bottomRight

    let left =
      movesLeft
      ? min(max(0, start.x + dx), startRight - minimum)
      : start.x
    let right =
      movesRight
      ? max(min(1, startRight + dx), start.x + minimum)
      : startRight
    let top =
      movesTop
      ? min(max(0, start.y + dy), startBottom - minimum)
      : start.y
    let bottom =
      movesBottom
      ? max(min(1, startBottom + dy), start.y + minimum)
      : startBottom

    return NormalizedCropRect(
      x: left,
      y: top,
      width: right - left,
      height: bottom - top
    ).clamped()
  }
}
