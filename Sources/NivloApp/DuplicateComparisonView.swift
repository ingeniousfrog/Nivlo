import AppKit
import NivloDomain
import SwiftUI

struct DuplicateComparisonView: View {
  let groups: [[ImageAsset]]
  let enrichments: [AssetID: AssetEnrichment]
  let language: NivloLanguage
  let onOpen: (ImageAsset) -> Void
  let onHide: (ImageAsset) -> Void

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 28) {
        ForEach(Array(groups.enumerated()), id: \.offset) { index, assets in
          VStack(alignment: .leading, spacing: 12) {
            Text("\(language.duplicateGroup) \(index + 1) · \(assets.count)")
              .font(.headline)
            ScrollView(.horizontal) {
              LazyHStack(alignment: .top, spacing: 14) {
                ForEach(assets) { asset in
                  duplicateCard(asset)
                }
              }
              .scrollTargetLayout()
            }
            .scrollIndicators(.visible)
          }
        }
      }
      .padding(24)
    }
  }

  private func duplicateCard(_ asset: ImageAsset) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Button {
        onOpen(asset)
      } label: {
        AssetImageView(
          asset: asset,
          enrichment: enrichments[asset.id],
          maxPixelSize: 700,
          contentMode: .fit
        )
        .frame(width: 300, height: 220)
        .background(.black.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
      }
      .buttonStyle(.plain)

      Text(asset.filename)
        .font(.headline)
        .lineLimit(1)
      Text(asset.url.deletingLastPathComponent().path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .textSelection(.enabled)
      LabeledContent(
        language.size,
        value: ByteCountFormatter.string(
          fromByteCount: asset.fileSize,
          countStyle: .file
        )
      )
      .font(.caption)
      if let width = asset.pixelWidth, let height = asset.pixelHeight {
        LabeledContent(language.dimensions, value: "\(width)×\(height)")
          .font(.caption)
      }

      HStack {
        Button(language.showInFinder) {
          NSWorkspace.shared.activateFileViewerSelecting([asset.url])
        }
        Button(language.copyPath) {
          NSPasteboard.general.clearContents()
          NSPasteboard.general.setString(asset.url.path, forType: .string)
        }
        Button(language.hideAsset, role: .destructive) {
          onHide(asset)
        }
      }
      .buttonStyle(.bordered)
      .controlSize(.small)
    }
    .frame(width: 300, alignment: .leading)
    .padding(14)
    .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 14))
  }
}
