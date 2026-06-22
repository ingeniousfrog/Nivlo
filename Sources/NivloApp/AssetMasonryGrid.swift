import NivloDomain
import SwiftUI

struct AssetMasonryGrid: View {
  let assets: [ImageAsset]
  let enrichments: [AssetID: AssetEnrichment]
  let selectedAssetIDs: Set<AssetID>
  let isSelecting: Bool
  let availableWidth: CGFloat
  let onOpen: (ImageAsset) -> Void
  let onToggleSelection: (AssetID) -> Void

  private let spacing: CGFloat = 16
  private let minimumColumnWidth: CGFloat = 210

  private var columnCount: Int {
    let count = Int((availableWidth + spacing) / (minimumColumnWidth + spacing))
    return min(7, max(2, count))
  }

  private var assetColumns: [[ImageAsset]] {
    AssetMasonryLayout.columns(for: assets, columnCount: columnCount)
  }

  var body: some View {
    HStack(alignment: .top, spacing: spacing) {
      ForEach(assetColumns.indices, id: \.self) { columnIndex in
        LazyVStack(spacing: spacing) {
          ForEach(assetColumns[columnIndex]) { asset in
            AssetCard(
              asset: asset,
              enrichment: enrichments[asset.id],
              isSelected: selectedAssetIDs.contains(asset.id)
            )
            .onTapGesture {
              if isSelecting {
                onToggleSelection(asset.id)
              } else {
                onOpen(asset)
              }
            }
          }
        }
        .frame(maxWidth: .infinity, alignment: .top)
      }
    }
  }
}
