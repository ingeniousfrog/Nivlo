import NivloImaging
import SwiftUI

struct ImageHistogramView: View {
  let histogram: ImageHistogram
  let shadowClippingLabel: String
  let highlightClippingLabel: String

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(spacing: 10) {
        channelLegend("R", color: .red)
        channelLegend("G", color: .green)
        channelLegend("B", color: .blue)
        channelLegend("L", color: .primary.opacity(0.85))
        Spacer(minLength: 0)
        clippingBadge(
          shadowClippingLabel,
          count: histogram.shadowClippingCount
        )
        clippingBadge(
          highlightClippingLabel,
          count: histogram.highlightClippingCount
        )
      }

      ZStack {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            LinearGradient(
              colors: [
                Color(red: 0.08, green: 0.09, blue: 0.11),
                Color(red: 0.12, green: 0.13, blue: 0.16),
              ],
              startPoint: .top,
              endPoint: .bottom
            )
          )

        Canvas { context, size in
          drawGrid(context: &context, size: size)
          draw(histogram.red.bins, color: .red.opacity(0.9), context: &context, size: size)
          draw(histogram.green.bins, color: .green.opacity(0.9), context: &context, size: size)
          draw(histogram.blue.bins, color: .blue.opacity(0.9), context: &context, size: size)
          draw(
            histogram.luminance.bins,
            color: .white.opacity(0.75),
            context: &context,
            size: size
          )
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
      }
      .frame(height: 88)
    }
    .accessibilityLabel("RGB and luminance histogram")
  }

  private func channelLegend(_ title: String, color: Color) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(color)
        .frame(width: 6, height: 6)
      Text(title)
        .font(.caption2.weight(.medium))
        .foregroundStyle(.secondary)
    }
  }

  private func clippingBadge(_ title: String, count: Int) -> some View {
    Text("\(title) \(count)")
      .font(.caption2.weight(.medium).monospacedDigit())
      .foregroundStyle(count > 0 ? Color.orange : Color.secondary)
      .padding(.horizontal, 7)
      .padding(.vertical, 3)
      .background(
        (count > 0 ? Color.orange : Color.secondary).opacity(0.12),
        in: Capsule()
      )
  }

  private func drawGrid(context: inout GraphicsContext, size: CGSize) {
    var grid = Path()
    for fraction in [0.25, 0.5, 0.75] {
      let x = size.width * fraction
      grid.move(to: CGPoint(x: x, y: 0))
      grid.addLine(to: CGPoint(x: x, y: size.height))
    }
    context.stroke(grid, with: .color(.white.opacity(0.08)), lineWidth: 0.5)
  }

  private func draw(
    _ bins: [Int],
    color: Color,
    context: inout GraphicsContext,
    size: CGSize
  ) {
    let maximum = max(1, bins.max() ?? 1)
    var path = Path()
    for (index, count) in bins.enumerated() {
      let x = CGFloat(index) / 255 * size.width
      let y = size.height - CGFloat(count) / CGFloat(maximum) * size.height
      if index == 0 {
        path.move(to: CGPoint(x: x, y: y))
      } else {
        path.addLine(to: CGPoint(x: x, y: y))
      }
    }
    context.stroke(path, with: .color(color), lineWidth: 1.25)
  }
}
