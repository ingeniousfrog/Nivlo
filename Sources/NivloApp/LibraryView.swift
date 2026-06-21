import AppKit
import NivloDomain
import NivloIndexing
import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
  private enum SectionSelection: Hashable {
    case allImages
    case spotlight
    case duplicates
    case similar
  }

  @StateObject private var model = LibraryModel()
  @State private var isChoosingFolder = false
  @State private var selection: SectionSelection? = .allImages

  private let columns = [
    GridItem(.adaptive(minimum: 180, maximum: 260), spacing: 16)
  ]

  var body: some View {
    NavigationSplitView {
      sidebar
    } detail: {
      content
    }
    .toolbar {
      ToolbarItem {
        Button {
          isChoosingFolder = true
        } label: {
          Label("Add Folder", systemImage: "folder.badge.plus")
        }
      }
    }
    .task {
      await model.loadLibrary()
    }
    .task {
      await model.discoverSpotlightCandidates()
    }
    .fileImporter(
      isPresented: $isChoosingFolder,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else {
        return
      }
      Task {
        await model.addFolder(url)
      }
    }
    .alert(
      "Couldn’t index this folder",
      isPresented: Binding(
        get: { model.errorMessage != nil },
        set: { isPresented in
          if !isPresented {
            model.errorMessage = nil
          }
        }
      )
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(model.errorMessage ?? "Unknown error")
    }
  }

  private var sidebar: some View {
    List(selection: $selection) {
      Section("Library") {
        Label("All Images", systemImage: "photo.on.rectangle.angled")
          .badge(model.assets.count)
          .tag(SectionSelection.allImages)
        Label("Spotlight Candidates", systemImage: "sparkle.magnifyingglass")
          .badge(model.spotlightCandidates.count)
          .tag(SectionSelection.spotlight)
        Label("Duplicates", systemImage: "square.on.square")
          .badge(model.duplicateGroups.count)
          .tag(SectionSelection.duplicates)
        Label("Similar", systemImage: "circle.grid.cross")
          .badge(model.similarGroups.count)
          .tag(SectionSelection.similar)
      }
      Section("Status") {
        Label(
          model.statusMessage,
          systemImage: model.isScanning
            ? "arrow.triangle.2.circlepath"
            : "checkmark.circle"
        )
        Label(
          model.spotlightStatusMessage,
          systemImage: model.isDiscoveringSpotlight
            ? "magnifyingglass"
            : "bolt.horizontal.circle"
        )
        Label(
          model.enrichmentStatusMessage,
          systemImage: model.isEnriching
            ? "wand.and.stars"
            : "photo.badge.checkmark"
        )
      }
      if !model.roots.isEmpty {
        Section("Folders") {
          ForEach(model.roots) { root in
            Button {
              Task {
                await model.rescan(root)
              }
            } label: {
              Label(root.displayName, systemImage: "folder")
            }
            .buttonStyle(.plain)
          }
        }
      }
    }
    .navigationSplitViewColumnWidth(min: 210, ideal: 240)
  }

  @ViewBuilder
  private var content: some View {
    if selection == .spotlight {
      spotlightContent
    } else if selection == .duplicates {
      groupedContent(
        title: "Exact Duplicates",
        emptyTitle: "No Exact Duplicates",
        emptyDescription: "Files with identical SHA-256 hashes appear here.",
        groups: model.duplicateGroups.map(\.assetIDs)
      )
    } else if selection == .similar {
      groupedContent(
        title: "Similar Images",
        emptyTitle: "No Similar Images",
        emptyDescription:
          "Images within the perceptual-hash similarity threshold appear here.",
        groups: model.similarGroups.map(\.assetIDs)
      )
    } else if model.assets.isEmpty {
      ContentUnavailableView {
        Label("Your visual library starts here", systemImage: "photo.stack")
      } description: {
        Text("Add a folder. Nivlo indexes images in place and never uploads the originals.")
      } actions: {
        Button("Add Folder") {
          isChoosingFolder = true
        }
        .buttonStyle(.borderedProminent)
      }
    } else {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(model.assets) { asset in
            AssetCard(
              asset: asset,
              enrichment: model.enrichments[asset.id]
            )
          }
        }
        .padding(24)
      }
      .navigationTitle("All Images")
    }
  }

  @ViewBuilder
  private func groupedContent(
    title: String,
    emptyTitle: String,
    emptyDescription: String,
    groups: [[AssetID]]
  ) -> some View {
    if groups.isEmpty {
      ContentUnavailableView(
        emptyTitle,
        systemImage: "square.stack.3d.up.slash",
        description: Text(emptyDescription)
      )
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: 28) {
          ForEach(Array(groups.enumerated()), id: \.offset) { index, assetIDs in
            VStack(alignment: .leading, spacing: 12) {
              Text("Group \(index + 1) · \(assetIDs.count) images")
                .font(.headline)
              LazyVGrid(columns: columns, spacing: 20) {
                ForEach(
                  model.assets.filter { assetIDs.contains($0.id) }
                ) { asset in
                  AssetCard(
                    asset: asset,
                    enrichment: model.enrichments[asset.id]
                  )
                }
              }
            }
          }
        }
        .padding(24)
      }
      .navigationTitle(title)
    }
  }

  @ViewBuilder
  private var spotlightContent: some View {
    if model.isDiscoveringSpotlight && model.spotlightCandidates.isEmpty {
      ProgressView("Finding images already indexed by macOS…")
    } else if model.spotlightCandidates.isEmpty {
      ContentUnavailableView(
        "No Spotlight Candidates",
        systemImage: "sparkle.magnifyingglass",
        description: Text(
          "Add a folder to scan it directly. Spotlight is only a quick discovery source."
        )
      )
    } else {
      ScrollView {
        VStack(alignment: .leading, spacing: 16) {
          Text(
            "These are lightweight suggestions from macOS metadata. Add their folders to build Nivlo’s complete local index."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
          LazyVGrid(columns: columns, spacing: 20) {
            ForEach(model.spotlightCandidates) { candidate in
              SpotlightCandidateCard(candidate: candidate)
            }
          }
        }
        .padding(24)
      }
      .navigationTitle("Spotlight Candidates")
    }
  }
}

private struct SpotlightCandidateCard: View {
  let candidate: SpotlightCandidate

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack {
        RoundedRectangle(cornerRadius: 12)
          .fill(.quaternary)
          .aspectRatio(4 / 3, contentMode: .fit)
        Image(systemName: "photo")
          .font(.system(size: 34))
          .foregroundStyle(.secondary)
      }
      Text(candidate.displayName)
        .font(.headline)
        .lineLimit(1)
      Text(candidate.url.deletingLastPathComponent().path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(1)
      if let width = candidate.pixelWidth, let height = candidate.pixelHeight {
        Text("\(width) × \(height)")
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    .contextMenu {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
      }
      Button("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(candidate.url.path, forType: .string)
      }
    }
  }
}

private struct AssetCard: View {
  let asset: ImageAsset
  let enrichment: AssetEnrichment?

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      thumbnail
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      Text(asset.filename)
        .font(.headline)
        .lineLimit(1)
      HStack {
        Text(asset.contentType.components(separatedBy: ".").last?.uppercased() ?? "IMAGE")
        Spacer()
        if let width = asset.pixelWidth, let height = asset.pixelHeight {
          Text("\(width) × \(height)")
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    .draggable(asset.url)
    .contextMenu {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
      }
      Button("Copy Path") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(asset.url.path, forType: .string)
      }
      Button("Copy Markdown Image") {
        let altText = asset.filename
          .replacingOccurrences(of: "[", with: "\\[")
          .replacingOccurrences(of: "]", with: "\\]")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(
          "![\(altText)](\(asset.url.path))",
          forType: .string
        )
      }
    }
  }

  @ViewBuilder
  private var thumbnail: some View {
    if let thumbnailURL = enrichment?.thumbnailURL,
      let image = NSImage(contentsOf: thumbnailURL)
    {
      Image(nsImage: image)
        .resizable()
        .scaledToFill()
    } else {
      ZStack {
        Color.secondary.opacity(0.12)
        Image(systemName: "photo")
          .font(.largeTitle)
          .foregroundStyle(.secondary)
      }
    }
  }
}
