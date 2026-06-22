import NivloDomain
import SwiftUI

extension Color {
  init(_ color: RGBAColor) {
    self.init(
      red: color.red,
      green: color.green,
      blue: color.blue,
      opacity: color.alpha
    )
  }

  fileprivate var rgbaColor: RGBAColor {
    let resolved = NSColor(self).usingColorSpace(.deviceRGB) ?? .white
    return RGBAColor(
      red: resolved.redComponent,
      green: resolved.greenComponent,
      blue: resolved.blueComponent,
      alpha: resolved.alphaComponent
    )
  }
}

struct AnnotationCanvasOverlay: View {
  @Binding var annotations: [ImageAnnotation]
  @Binding var selectedAnnotationID: UUID?
  let isEditing: Bool

  var body: some View {
    GeometryReader { proxy in
      ZStack {
        ForEach($annotations) { $annotation in
          AnnotationObjectView(
            annotation: $annotation,
            isSelected: isEditing && selectedAnnotationID == annotation.id,
            isEditing: isEditing,
            canvasSize: proxy.size,
            onSelect: {
              selectedAnnotationID = annotation.id
            }
          )
        }
      }
    }
    .allowsHitTesting(isEditing)
  }
}

private struct AnnotationObjectView: View {
  @Binding var annotation: ImageAnnotation
  let isSelected: Bool
  let isEditing: Bool
  let canvasSize: CGSize
  let onSelect: () -> Void

  @State private var activeHandle: NormalizedCropHandle?
  @State private var dragStartRect = NormalizedCropRect.full

  var body: some View {
    let rect = pixelRect(annotation.normalizedRect.clamped())
    ZStack {
      annotationContent
        .frame(width: rect.width, height: rect.height)
        .position(x: rect.midX, y: rect.midY)
        .contentShape(Rectangle())
        .onTapGesture {
          onSelect()
        }
        .gesture(dragGesture(for: .move))

      if isSelected {
        selectionBorder(rect: rect)
        ForEach(cornerHandles(in: rect), id: \.handle) { item in
          resizeHandle(item)
        }
      }
    }
    .frame(width: canvasSize.width, height: canvasSize.height)
  }

  @ViewBuilder
  private var annotationContent: some View {
    switch annotation.kind {
    case .text:
      Text(annotation.text.isEmpty ? "Text" : annotation.text)
        .font(annotationFont)
        .foregroundStyle(Color(annotation.textStyle.color))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .minimumScaleFactor(0.4)
    case .rectangle:
      Rectangle()
        .fill(Color(annotation.rectangleStyle.fillColor))
        .overlay {
          Rectangle()
            .stroke(
              Color(annotation.rectangleStyle.strokeColor),
              style: strokeStyle(
                width: annotation.rectangleStyle.lineWidth,
                lineStyle: annotation.rectangleStyle.lineStyle
              )
            )
        }
    case .arrow:
      ArrowShape(direction: annotation.arrowStyle.direction)
        .stroke(
          Color(annotation.arrowStyle.color),
          style: StrokeStyle(
            lineWidth: annotation.arrowStyle.lineWidth,
            lineCap: .round,
            lineJoin: .round
          )
        )
        .padding(max(8, annotation.arrowStyle.lineWidth))
    }
  }

  private var annotationFont: Font {
    var font = Font.custom(
      annotation.textStyle.fontName,
      size: annotation.textStyle.fontSize
    )
    if annotation.textStyle.isBold {
      font = font.weight(.bold)
    }
    if annotation.textStyle.isItalic {
      font = font.italic()
    }
    return font
  }

  private func selectionBorder(rect: CGRect) -> some View {
    Rectangle()
      .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
      .frame(width: rect.width, height: rect.height)
      .position(x: rect.midX, y: rect.midY)
      .allowsHitTesting(false)
  }

  private func resizeHandle(
    _ item: (handle: NormalizedCropHandle, point: CGPoint)
  ) -> some View {
    ZStack {
      Color.clear
      Circle()
        .fill(Color.white)
        .overlay {
          Circle().stroke(Color.accentColor, lineWidth: 2)
        }
        .frame(width: 12, height: 12)
    }
    .frame(width: 28, height: 28)
    .position(item.point)
    .highPriorityGesture(dragGesture(for: item.handle))
  }

  private func dragGesture(for handle: NormalizedCropHandle) -> some Gesture {
    DragGesture(minimumDistance: 0)
      .onChanged { value in
        onSelect()
        if activeHandle == nil {
          activeHandle = handle
          dragStartRect = annotation.normalizedRect.clamped()
        }
        guard activeHandle == handle else { return }
        annotation.normalizedRect = dragStartRect.applying(
          handle: handle,
          translation: value.translation,
          canvasSize: canvasSize,
          minimumSize: 0.04
        )
      }
      .onEnded { _ in
        activeHandle = nil
      }
  }

  private func pixelRect(_ rect: NormalizedCropRect) -> CGRect {
    CGRect(
      x: rect.x * canvasSize.width,
      y: rect.y * canvasSize.height,
      width: rect.width * canvasSize.width,
      height: rect.height * canvasSize.height
    )
  }

  private func cornerHandles(
    in rect: CGRect
  ) -> [(handle: NormalizedCropHandle, point: CGPoint)] {
    [
      (.topLeft, CGPoint(x: rect.minX, y: rect.minY)),
      (.topRight, CGPoint(x: rect.maxX, y: rect.minY)),
      (.bottomRight, CGPoint(x: rect.maxX, y: rect.maxY)),
      (.bottomLeft, CGPoint(x: rect.minX, y: rect.maxY)),
    ]
  }

  private func strokeStyle(
    width: Double,
    lineStyle: AnnotationLineStyle
  ) -> StrokeStyle {
    let dash: [CGFloat]
    switch lineStyle {
    case .solid:
      dash = []
    case .dashed:
      dash = [12, 8]
    case .dashDot:
      dash = [12, 6, 2, 6]
    }
    return StrokeStyle(lineWidth: width, lineJoin: .round, dash: dash)
  }
}

struct ArrowShape: Shape {
  let direction: ArrowDirection

  func path(in rect: CGRect) -> Path {
    var path = Path()
    let start = CGPoint(x: rect.minX, y: rect.maxY)
    let end = CGPoint(x: rect.maxX, y: rect.minY)
    path.move(to: start)
    path.addLine(to: end)
    if direction == .forward || direction == .both {
      addHead(to: &path, tip: end, from: start)
    }
    if direction == .backward || direction == .both {
      addHead(to: &path, tip: start, from: end)
    }
    return path
  }

  private func addHead(to path: inout Path, tip: CGPoint, from: CGPoint) {
    let angle = atan2(tip.y - from.y, tip.x - from.x)
    let length = max(12, min(28, hypot(tip.x - from.x, tip.y - from.y) * 0.18))
    for offset in [CGFloat.pi * 0.78, -CGFloat.pi * 0.78] {
      path.move(to: tip)
      path.addLine(
        to: CGPoint(
          x: tip.x + cos(angle + offset) * length,
          y: tip.y + sin(angle + offset) * length
        )
      )
    }
  }
}

struct RGBAColorPicker: View {
  let title: String
  @Binding var color: RGBAColor

  var body: some View {
    ColorPicker(
      title,
      selection: Binding(
        get: { Color(color) },
        set: { color = $0.rgbaColor }
      ),
      supportsOpacity: true
    )
  }
}
