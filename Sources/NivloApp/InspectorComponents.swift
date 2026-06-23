import SwiftUI

struct InspectorSection<Content: View>: View {
  let title: String
  @ViewBuilder var content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
        .tracking(0.35)

      VStack(alignment: .leading, spacing: 0, content: content)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(inspectorPanelBackground)
    }
  }
}

struct InspectorField: View {
  let label: String
  let value: String
  var monospacedValue = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: InspectorMetrics.labelWidth, alignment: .leading)

      Text(value)
        .font(monospacedValue ? .callout.monospacedDigit() : .callout)
        .foregroundStyle(.primary)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.vertical, 3)
  }
}

struct InspectorFieldPair: View {
  let leading: InspectorFieldModel
  let trailing: InspectorFieldModel?

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      fieldColumn(leading)
      if let trailing {
        fieldColumn(trailing)
      } else {
        Spacer(minLength: 0)
      }
    }
    .padding(.vertical, 2)
  }

  private func fieldColumn(_ model: InspectorFieldModel) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(model.label)
        .font(.caption2)
        .foregroundStyle(.secondary)
      Text(model.value)
        .font(model.monospaced ? .callout.monospacedDigit() : .callout)
        .textSelection(.enabled)
        .lineLimit(2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

struct InspectorFieldModel: Identifiable {
  let id: String
  let label: String
  let value: String
  var monospaced = false

  init(label: String, value: String, monospaced: Bool = false) {
    self.id = label
    self.label = label
    self.value = value
    self.monospaced = monospaced
  }
}

struct InspectorDivider: View {
  var body: some View {
    Divider()
      .padding(.vertical, 6)
  }
}

struct InspectorTagRow: View {
  let label: String
  let tags: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)

      FlowLayout(spacing: 6) {
        ForEach(tags, id: \.self) { tag in
          Text(tag)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(.quaternary.opacity(0.55), in: Capsule())
        }
      }
    }
    .padding(.vertical, 4)
  }
}

struct InspectorColorPalette: View {
  let label: String
  let colors: [String]

  var body: some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(label)
        .font(.caption)
        .foregroundStyle(.secondary)

      HStack(spacing: 8) {
        ForEach(colors, id: \.self) { hex in
          VStack(spacing: 4) {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
              .fill(InspectorColorParser.color(from: hex))
              .frame(width: 28, height: 28)
              .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                  .strokeBorder(.primary.opacity(0.12), lineWidth: 0.5)
              )
            Text(hex.uppercased())
              .font(.system(size: 9, design: .monospaced))
              .foregroundStyle(.secondary)
              .lineLimit(1)
          }
        }
      }
    }
    .padding(.vertical, 4)
  }
}

enum InspectorMetrics {
  static let labelWidth: CGFloat = 88
}

private var inspectorPanelBackground: some View {
  RoundedRectangle(cornerRadius: 10, style: .continuous)
    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.72))
    .overlay(
      RoundedRectangle(cornerRadius: 10, style: .continuous)
        .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
    )
}

private struct FlowLayout: Layout {
  var spacing: CGFloat = 8

  func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
    let width = proposal.width ?? 0
    guard width > 0 else { return .zero }
    var x: CGFloat = 0
    var y: CGFloat = 0
    var rowHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > 0, x + size.width > width {
        x = 0
        y += rowHeight + spacing
        rowHeight = 0
      }
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
    }
    return CGSize(width: width, height: y + rowHeight)
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    var x = bounds.minX
    var y = bounds.minY
    var rowHeight: CGFloat = 0
    for subview in subviews {
      let size = subview.sizeThatFits(.unspecified)
      if x > bounds.minX, x + size.width > bounds.maxX {
        x = bounds.minX
        y += rowHeight + spacing
        rowHeight = 0
      }
      subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
      rowHeight = max(rowHeight, size.height)
      x += size.width + spacing
    }
  }
}

enum InspectorColorParser {
  static func color(from hex: String) -> Color {
    let sanitized = hex.trimmingCharacters(in: .whitespacesAndNewlines)
      .replacingOccurrences(of: "#", with: "")
    guard sanitized.count == 6, let value = UInt64(sanitized, radix: 16) else {
      return Color.secondary.opacity(0.35)
    }
    let red = Double((value >> 16) & 0xFF) / 255
    let green = Double((value >> 8) & 0xFF) / 255
    let blue = Double(value & 0xFF) / 255
    return Color(red: red, green: green, blue: blue)
  }
}
