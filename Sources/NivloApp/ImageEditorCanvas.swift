import NivloDomain
import SwiftUI

struct EditorImageLayout {
  let imageSize: CGSize
  let containerSize: CGSize

  var contentRect: CGRect {
    guard imageSize.width > 0, imageSize.height > 0 else {
      return CGRect(origin: .zero, size: containerSize)
    }
    let scale = min(
      containerSize.width / imageSize.width,
      containerSize.height / imageSize.height
    )
    let fitted = CGSize(
      width: imageSize.width * scale,
      height: imageSize.height * scale
    )
    return CGRect(
      x: (containerSize.width - fitted.width) / 2,
      y: (containerSize.height - fitted.height) / 2,
      width: fitted.width,
      height: fitted.height
    )
  }
}

struct InteractiveCropOverlay: View {
  @Binding var cropRect: NormalizedCropRect

  @State private var activeHandle: NormalizedCropHandle?
  @State private var dragStartRect = NormalizedCropRect.full

  var body: some View {
    GeometryReader { proxy in
      let canvasSize = proxy.size
      let rect = pixelRect(for: cropRect.clamped(), in: canvasSize)

      ZStack {
        cropShade(canvasSize: canvasSize, cropRect: rect)
        moveSurface(rect: rect, canvasSize: canvasSize)
        moveHandle(rect: rect)

        ForEach(handlePositions(in: rect, canvasSize: canvasSize), id: \.handle) { item in
          cropHandle(item)
        }
        Color.clear
          .contentShape(Rectangle())
          .gesture(unifiedDragGesture(canvasSize: canvasSize))
          .zIndex(3)
      }
    }
  }

  private func moveHandle(rect: CGRect) -> some View {
    ZStack {
      Circle()
        .fill(Color.accentColor.opacity(0.9))
        .frame(width: 20, height: 20)
      Image(systemName: "arrow.up.and.down.and.arrow.left.and.right")
        .font(.system(size: 9, weight: .bold))
        .foregroundStyle(.white)
    }
    .frame(width: 34, height: 34)
    .position(x: rect.midX, y: rect.midY)
    .contentShape(Rectangle())
    .zIndex(2)
    .accessibilityLabel(accessibilityLabel(for: .move))
  }

  private func cropShade(canvasSize: CGSize, cropRect: CGRect) -> some View {
    Path { path in
      path.addRect(CGRect(origin: .zero, size: canvasSize))
      path.addRect(cropRect)
    }
    .fill(Color.black.opacity(0.48), style: FillStyle(eoFill: true))
    .allowsHitTesting(false)
  }

  private func moveSurface(rect: CGRect, canvasSize: CGSize) -> some View {
    Rectangle()
      .strokeBorder(Color.accentColor, lineWidth: 2)
      .background(Color.accentColor.opacity(0.06))
      .frame(width: rect.width, height: rect.height)
      .position(x: rect.midX, y: rect.midY)
      .contentShape(Rectangle())
      .zIndex(0)
  }

  private func cropHandle(
    _ item: (handle: NormalizedCropHandle, point: CGPoint)
  ) -> some View {
    ZStack {
      Color.clear
      RoundedRectangle(cornerRadius: 3)
        .fill(Color.accentColor)
        .frame(width: 14, height: 14)
        .overlay {
          RoundedRectangle(cornerRadius: 3)
            .stroke(Color.white.opacity(0.9), lineWidth: 1)
        }
    }
    .frame(width: 30, height: 30)
    .position(item.point)
    .contentShape(Rectangle())
    .zIndex(1)
    .accessibilityLabel(accessibilityLabel(for: item.handle))
  }

  private func unifiedDragGesture(canvasSize: CGSize) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        if activeHandle == nil {
          activeHandle = CropInteractionTarget.resolve(
            location: value.startLocation,
            cropRect: cropRect,
            canvasSize: canvasSize
          )
          dragStartRect = cropRect.clamped()
        }
        guard let activeHandle else { return }
        cropRect = dragStartRect.applying(
          handle: activeHandle,
          translation: value.translation,
          canvasSize: canvasSize
        )
      }
      .onEnded { _ in
        activeHandle = nil
        cropRect = cropRect.clamped()
      }
  }

  private func pixelRect(for crop: NormalizedCropRect, in size: CGSize) -> CGRect {
    CGRect(
      x: crop.x * size.width,
      y: crop.y * size.height,
      width: crop.width * size.width,
      height: crop.height * size.height
    )
  }

  private func handlePositions(
    in rect: CGRect,
    canvasSize: CGSize
  ) -> [(handle: NormalizedCropHandle, point: CGPoint)] {
    let inset: CGFloat = 10
    let left = min(max(inset, rect.minX), max(inset, canvasSize.width - inset))
    let right = min(max(inset, rect.maxX), max(inset, canvasSize.width - inset))
    let top = min(max(inset, rect.minY), max(inset, canvasSize.height - inset))
    let bottom = min(max(inset, rect.maxY), max(inset, canvasSize.height - inset))
    return [
      (.topLeft, CGPoint(x: left, y: top)),
      (.top, CGPoint(x: rect.midX, y: top)),
      (.topRight, CGPoint(x: right, y: top)),
      (.right, CGPoint(x: right, y: rect.midY)),
      (.bottomRight, CGPoint(x: right, y: bottom)),
      (.bottom, CGPoint(x: rect.midX, y: bottom)),
      (.bottomLeft, CGPoint(x: left, y: bottom)),
      (.left, CGPoint(x: left, y: rect.midY)),
    ]
  }

  private func accessibilityLabel(for handle: NormalizedCropHandle) -> String {
    switch handle {
    case .move:
      "Move crop"
    case .topLeft:
      "Resize crop from top left"
    case .top:
      "Resize crop from top"
    case .topRight:
      "Resize crop from top right"
    case .right:
      "Resize crop from right"
    case .bottomRight:
      "Resize crop from bottom right"
    case .bottom:
      "Resize crop from bottom"
    case .bottomLeft:
      "Resize crop from bottom left"
    case .left:
      "Resize crop from left"
    }
  }
}

struct MaskBrushOverlay: View {
  let strokes: [MaskStroke]
  let currentStroke: MaskStroke?

  var body: some View {
    Canvas { context, canvasSize in
      let allStrokes = strokes + (currentStroke.map { [$0] } ?? [])
      context.drawLayer { layer in
        for stroke in allStrokes where !stroke.points.isEmpty {
          layer.blendMode = stroke.operation == .paint ? .normal : .destinationOut
          draw(stroke: stroke, context: &layer, canvasSize: canvasSize)
        }
      }
    }
    .allowsHitTesting(false)
  }

  private func draw(
    stroke: MaskStroke,
    context: inout GraphicsContext,
    canvasSize: CGSize
  ) {
    let lineWidth = max(
      6,
      CGFloat(stroke.brushRadius) * min(canvasSize.width, canvasSize.height) * 2
    )
    if stroke.points.count == 1, let point = stroke.points.first {
      let center = pointLocation(point, in: canvasSize)
      let dot = CGRect(
        x: center.x - lineWidth / 2,
        y: center.y - lineWidth / 2,
        width: lineWidth,
        height: lineWidth
      )
      context.fill(Path(ellipseIn: dot), with: .color(.red.opacity(0.55)))
      return
    }

    var path = Path()
    path.move(to: pointLocation(stroke.points[0], in: canvasSize))
    for point in stroke.points.dropFirst() {
      path.addLine(to: pointLocation(point, in: canvasSize))
    }
    context.stroke(
      path,
      with: .color(.red.opacity(0.55)),
      style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
    )
  }

  private func pointLocation(_ point: MaskBrushPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: point.x * size.width, y: point.y * size.height)
  }
}

struct MaskPaintingSurface: View {
  @Binding var maskStrokes: [MaskStroke]
  @Binding var currentMaskStroke: MaskStroke?
  let brushRadius: Double
  let operation: MaskStrokeOperation

  var body: some View {
    GeometryReader { proxy in
      Color.clear
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0)
            .onChanged { value in
              addPoint(normalizedPoint(location: value.location, in: proxy.size))
            }
            .onEnded { _ in
              if let stroke = currentMaskStroke, !stroke.points.isEmpty {
                maskStrokes = maskStrokes + [stroke]
              }
              currentMaskStroke = nil
            }
        )
    }
  }

  private func addPoint(_ point: MaskBrushPoint) {
    guard let stroke = currentMaskStroke else {
      currentMaskStroke = MaskStroke(
        points: [point],
        brushRadius: brushRadius,
        operation: operation
      )
      return
    }
    let addedPoints =
      stroke.points.last.map {
        interpolatedPoints(from: $0, to: point, brushRadius: brushRadius)
      } ?? [point]
    currentMaskStroke = MaskStroke(
      id: stroke.id,
      points: stroke.points + addedPoints,
      brushRadius: brushRadius,
      operation: operation
    )
  }

  private func normalizedPoint(location: CGPoint, in size: CGSize) -> MaskBrushPoint {
    guard size.width > 0, size.height > 0 else {
      return MaskBrushPoint(x: 0, y: 0)
    }
    return MaskBrushPoint(
      x: Double(min(max(0, location.x / size.width), 1)),
      y: Double(min(max(0, location.y / size.height), 1))
    )
  }

  private func interpolatedPoints(
    from start: MaskBrushPoint,
    to end: MaskBrushPoint,
    brushRadius: Double
  ) -> [MaskBrushPoint] {
    let dx = end.x - start.x
    let dy = end.y - start.y
    let distance = hypot(dx, dy)
    let step = max(brushRadius / 4, 0.004)
    guard distance > step else { return [end] }

    let stepCount = max(1, Int(ceil(distance / step)))
    return (1...stepCount).map { index in
      let progress = min(Double(index) * step / distance, 1)
      return MaskBrushPoint(
        x: start.x + dx * progress,
        y: start.y + dy * progress
      )
    }
  }
}
