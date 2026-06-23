import AppKit
import NivloImaging
import SwiftUI

struct VideoTimelineView: View {
  let thumbnails: [VideoTimelineThumbnail]
  let waveform: [Double]
  let durationSeconds: Double
  let currentSeconds: Double
  let startSeconds: Double
  let endSeconds: Double
  let onSeek: (Double) -> Void

  var body: some View {
    GeometryReader { proxy in
      let width = max(proxy.size.width, 1)
      ZStack(alignment: .topLeading) {
        HStack(spacing: 2) {
          ForEach(Array(thumbnails.enumerated()), id: \.offset) { _, thumbnail in
            if let image = NSImage(data: thumbnail.imageData) {
              Image(nsImage: image)
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
          }
        }
        WaveformShape(samples: waveform)
          .stroke(.white.opacity(0.85), lineWidth: 1)
          .padding(.vertical, 8)
          .blendMode(.plusLighter)
        trimShade(width: width, height: proxy.size.height)
        marker(
          x: position(currentSeconds, width: width),
          color: .yellow,
          width: 2,
          height: proxy.size.height
        )
        marker(
          x: position(startSeconds, width: width),
          color: .green,
          width: 3,
          height: proxy.size.height
        )
        marker(
          x: position(endSeconds, width: width),
          color: .red,
          width: 3,
          height: proxy.size.height
        )
        Color.clear
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0)
              .onChanged { value in
                onSeek(
                  min(
                    max(0, Double(value.location.x / width) * durationSeconds),
                    durationSeconds
                  )
                )
              }
          )
      }
      .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    .frame(height: 112)
    .background(.black, in: RoundedRectangle(cornerRadius: 8))
  }

  private func trimShade(width: CGFloat, height: CGFloat) -> some View {
    let startX = position(startSeconds, width: width)
    let endX = position(endSeconds, width: width)
    return Path { path in
      path.addRect(CGRect(x: 0, y: 0, width: startX, height: height))
      path.addRect(
        CGRect(
          x: endX,
          y: 0,
          width: max(0, width - endX),
          height: height
        )
      )
    }
    .fill(.black.opacity(0.58))
  }

  private func marker(
    x: CGFloat,
    color: Color,
    width: CGFloat,
    height: CGFloat
  ) -> some View {
    Rectangle()
      .fill(color)
      .frame(width: width, height: height)
      .offset(x: x - width / 2)
  }

  private func position(_ seconds: Double, width: CGFloat) -> CGFloat {
    guard durationSeconds > 0 else { return 0 }
    return CGFloat(min(max(seconds / durationSeconds, 0), 1)) * width
  }
}

private struct WaveformShape: Shape {
  let samples: [Double]

  func path(in rect: CGRect) -> Path {
    guard !samples.isEmpty else { return Path() }
    var path = Path()
    let centerY = rect.midY
    for (index, sample) in samples.enumerated() {
      let x =
        rect.minX
        + CGFloat(index) / CGFloat(max(1, samples.count - 1)) * rect.width
      let amplitude = CGFloat(min(max(sample, 0), 1)) * rect.height * 0.45
      path.move(to: CGPoint(x: x, y: centerY - amplitude))
      path.addLine(to: CGPoint(x: x, y: centerY + amplitude))
    }
    return path
  }
}
