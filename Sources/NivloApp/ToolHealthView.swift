import NivloImaging
import SwiftUI

struct ToolHealthView: View {
  @ObservedObject var bootstrapper: ToolBootstrapper
  let language: NivloLanguage
  var compact = false

  var body: some View {
    if compact {
      HStack(spacing: 8) {
        statusIcon
        VStack(alignment: .leading, spacing: 1) {
          Text(language.toolsStatusTitle)
            .font(.caption)
          Text(bootstrapper.statusMessage)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        if bootstrapper.manifest.phase == .failed {
          Button(language.retry) {
            bootstrapper.retry()
          }
          .controlSize(.mini)
        }
      }
    } else {
      HStack(spacing: 10) {
        statusIcon
        VStack(alignment: .leading, spacing: 2) {
          Text(language.toolsStatusTitle)
            .font(.caption.weight(.semibold))
          Text(bootstrapper.statusMessage)
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(2)
        }
        if bootstrapper.manifest.phase == .failed {
          Button(language.retry) {
            bootstrapper.retry()
          }
          .controlSize(.small)
        }
      }
      .padding(.horizontal, 12)
      .padding(.vertical, 8)
      .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
    }
  }

  @ViewBuilder
  private var statusIcon: some View {
    Image(
      systemName: bootstrapper.isReady
        ? "checkmark.circle.fill"
        : bootstrapper.manifest.phase == .failed
          ? "exclamationmark.triangle.fill"
          : "arrow.triangle.2.circlepath"
    )
    .foregroundStyle(
      bootstrapper.isReady
        ? .green
        : bootstrapper.manifest.phase == .failed ? .orange : .primary.opacity(0.55)
    )
  }
}
