import AppKit
import NivloDomain
import SwiftUI

struct LineageView: View {
  let graph: AssetLineageGraph
  let language: NivloLanguage

  var body: some View {
    if graph.nodes.isEmpty {
      ContentUnavailableView(
        language.noLineageTitle,
        systemImage: "point.3.connected.trianglepath.dotted",
        description: Text(language.noLineageDescription)
      )
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 12) {
          ForEach(graph.nodes) { node in
            lineageRow(node.record)
            if node.id != graph.nodes.last?.id {
              Image(systemName: "arrow.down")
                .foregroundStyle(.secondary)
                .padding(.leading, 8)
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
      }
    }
  }

  private func lineageRow(_ record: ProcessingHistoryRecord) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      HStack {
        Text(record.derivativeKind.rawValue.capitalized)
          .font(.caption.weight(.semibold))
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .background(.quaternary, in: Capsule())
        Text(record.operation.rawValue)
          .font(.caption)
          .foregroundStyle(.secondary)
        Spacer()
        Text(record.createdAt, style: .date)
          .font(.caption2)
          .foregroundStyle(.secondary)
      }
      Text(record.outputURL.lastPathComponent)
        .font(.subheadline)
        .lineLimit(1)
      HStack(spacing: 8) {
        Button(language.showInFinder) {
          NSWorkspace.shared.activateFileViewerSelecting([record.outputURL])
        }
        .controlSize(.small)
        if let parent = record.parentRecordID {
          Text("Parent: \(parent.uuidString.prefix(8))…")
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
      }
    }
    .padding(12)
    .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
  }
}
