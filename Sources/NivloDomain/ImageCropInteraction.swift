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

public enum CropInteractionTarget {
  public static func resolve(
    location: CGPoint,
    cropRect: NormalizedCropRect,
    canvasSize: CGSize,
    hitRadius: CGFloat = 24
  ) -> NormalizedCropHandle? {
    guard canvasSize.width > 0, canvasSize.height > 0 else {
      return nil
    }
    let crop = cropRect.clamped()
    let rect = CGRect(
      x: crop.x * canvasSize.width,
      y: crop.y * canvasSize.height,
      width: crop.width * canvasSize.width,
      height: crop.height * canvasSize.height
    )
    let targets: [(NormalizedCropHandle, CGPoint)] = [
      (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
      (.top, CGPoint(x: rect.midX, y: rect.minY)),
      (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
      (.right, CGPoint(x: rect.maxX, y: rect.midY)),
      (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
      (.bottom, CGPoint(x: rect.midX, y: rect.maxY)),
      (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
      (.left, CGPoint(x: rect.minX, y: rect.midY)),
      (.move, CGPoint(x: rect.midX, y: rect.midY)),
    ]
    if let nearest =
      targets
      .map({ target in
        (
          handle: target.0,
          distance: hypot(location.x - target.1.x, location.y - target.1.y)
        )
      })
      .filter({ $0.distance <= hitRadius })
      .min(by: { $0.distance < $1.distance })
    {
      return nearest.handle
    }
    return rect.contains(location) ? .move : nil
  }
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
