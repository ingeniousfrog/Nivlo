import AppKit
import SwiftUI

enum ImageEditorTool: String, CaseIterable, Identifiable {
  case geometry
  case adjust
  case annotate
  case mask

  var id: String { rawValue }

  func title(language: NivloLanguage) -> String {
    switch self {
    case .geometry: language.tabGeometry
    case .adjust: language.tabAdjust
    case .annotate: language.tabAnnotate
    case .mask: language.tabMask
    }
  }

  var icon: String {
    switch self {
    case .geometry: "crop.rotate"
    case .adjust: "slider.horizontal.3"
    case .annotate: "pencil.and.outline"
    case .mask: "paintbrush.pointed"
    }
  }
}

struct ImageEditorToolSelector: View {
  let language: NivloLanguage
  @Binding var selection: ImageEditorTool
  let onSelect: (ImageEditorTool) -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(language.editorTools)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)

      HStack(spacing: 3) {
        ForEach(ImageEditorTool.allCases) { tool in
          Button {
            selection = tool
            onSelect(tool)
          } label: {
            HStack(spacing: 4) {
              Image(systemName: tool.icon)
              Text(tool.title(language: language))
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .font(.caption.weight(selection == tool ? .semibold : .regular))
            .frame(maxWidth: .infinity, minHeight: 28)
            .padding(.horizontal, 6)
            .contentShape(Capsule())
          }
          .buttonStyle(.plain)
          .foregroundStyle(selection == tool ? Color.accentColor : .primary)
          .background {
            if selection == tool {
              Capsule().fill(Color.accentColor.opacity(0.16))
            }
          }
          .accessibilityLabel(tool.title(language: language))
        }
      }
      .padding(4)
      .background(
        Color(nsColor: .controlBackgroundColor),
        in: Capsule()
      )
    }
  }
}
