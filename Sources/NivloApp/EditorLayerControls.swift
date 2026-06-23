import NivloDomain
import SwiftUI

struct EditorLayerControls: View {
  let language: NivloLanguage
  @Binding var layers: [EditorLayer]

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Text(language.layers)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .textCase(.uppercase)
      Text(language.layerControlsHint)
        .font(.caption2)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)

      ForEach(Array(layers.enumerated()), id: \.element.id) { index, layer in
        HStack(spacing: 8) {
          Text(layerTitle(layer.kind))
            .lineLimit(1)
          Spacer()
          Button {
            let binding = visibilityBinding(for: layer.id)
            binding.wrappedValue.toggle()
          } label: {
            Image(
              systemName: layer.isVisible ? "eye.fill" : "eye.slash"
            )
          }
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help(layer.isVisible ? language.hideLayer : language.showLayer)
          Button {
            moveLayer(at: index, offset: -1)
          } label: {
            Image(systemName: "chevron.up")
          }
          .disabled(index <= 1)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help(language.moveLayerUp)
          Button {
            moveLayer(at: index, offset: 1)
          } label: {
            Image(systemName: "chevron.down")
          }
          .disabled(index == 0 || index >= layers.count - 1)
          .buttonStyle(.bordered)
          .controlSize(.small)
          .help(language.moveLayerDown)
        }
      }
    }
  }

  private func visibilityBinding(for id: UUID) -> Binding<Bool> {
    Binding(
      get: { layers.first(where: { $0.id == id })?.isVisible ?? false },
      set: { value in
        guard let index = layers.firstIndex(where: { $0.id == id }) else {
          return
        }
        var updated = layers
        updated[index].isVisible = value
        layers = updated
      }
    )
  }

  private func moveLayer(at index: Int, offset: Int) {
    let destination = index + offset
    guard
      index > 0,
      layers.indices.contains(index),
      layers.indices.contains(destination),
      destination > 0
    else {
      return
    }
    var updated = layers
    let layer = updated.remove(at: index)
    updated.insert(layer, at: destination)
    layers = updated
  }

  private func layerTitle(_ kind: EditorLayerKind) -> String {
    switch kind {
    case .background:
      language.layerBackground
    case .adjustments:
      language.layerAdjustments
    case .localAdjustments:
      language.layerLocalAdjustments
    case .annotations:
      language.layerAnnotations
    case .mask:
      language.layerMask
    }
  }
}
