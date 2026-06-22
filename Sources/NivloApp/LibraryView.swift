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
    case smart(SmartAssetView)
  }

  @StateObject private var model = LibraryModel()
  @State private var selection: SectionSelection? = .allImages
  @State private var searchText = ""
  @State private var selectedAssetIDs: Set<AssetID> = []
  @State private var previewAsset: ImageAsset?
  @State private var folderPendingRemoval: LibraryRoot?
  @State private var folderFilter: String?
  @State private var sourceFilter: AssetSource?
  @State private var formatFilter: FormatFilter = .all
  @State private var timeFilter: TimeFilter = .all
  @State private var sizeFilter: SizeFilter = .all
  @State private var dimensionFilter: DimensionFilter = .all
  @State private var sortOption: SortOption = .path

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
          chooseFolderToIndex()
        } label: {
          Label("Add Folder", systemImage: "folder.badge.plus")
        }
      }
      ToolbarItem {
        Menu {
          Picker("Folder", selection: $folderFilter) {
            Text("All Folders").tag(nil as String?)
            ForEach(model.roots) { root in
              Text(root.displayName).tag(root.pathHint as String?)
            }
          }
          Picker("Source", selection: $sourceFilter) {
            Text("All Sources").tag(nil as AssetSource?)
            ForEach(AssetSource.allCases, id: \.self) { source in
              Text(source.title).tag(source as AssetSource?)
            }
          }
          Picker("Format", selection: $formatFilter) {
            ForEach(FormatFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          Picker("Time", selection: $timeFilter) {
            ForEach(TimeFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          Picker("Size", selection: $sizeFilter) {
            ForEach(SizeFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          Picker("Dimensions", selection: $dimensionFilter) {
            ForEach(DimensionFilter.allCases) { filter in
              Text(filter.title).tag(filter)
            }
          }
          Picker("Sort", selection: $sortOption) {
            ForEach(SortOption.allCases) { option in
              Text(option.title).tag(option)
            }
          }
        } label: {
          Label("Filter", systemImage: "line.3.horizontal.decrease.circle")
        }
      }
      ToolbarItem {
        Button {
          chooseExportFolder()
        } label: {
          Label("Export Selected", systemImage: "square.and.arrow.up")
        }
        .disabled(selectedAssetIDs.isEmpty)
      }
    }
    .searchable(
      text: $searchText,
      placement: .toolbar,
      prompt: "Search filename, path, OCR, keywords"
    )
    .task {
      await model.loadLibrary()
    }
    .task {
      await model.discoverSpotlightCandidates()
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
    .sheet(item: $previewAsset) { asset in
      AssetPreviewPanel(
        asset: asset,
        enrichment: model.enrichments[asset.id],
        isSelected: selectedAssetIDs.contains(asset.id),
        onToggleSelection: {
          toggleSelection(asset.id)
        },
        onExport: {
          chooseExportFolder(assetIDs: [asset.id])
        }
      )
    }
    .alert(
      "Remove folder from Nivlo?",
      isPresented: Binding(
        get: { folderPendingRemoval != nil },
        set: { isPresented in
          if !isPresented {
            folderPendingRemoval = nil
          }
        }
      ),
      presenting: folderPendingRemoval
    ) { root in
      Button("Remove", role: .destructive) {
        removeFolder(root)
      }
      Button("Cancel", role: .cancel) {
        folderPendingRemoval = nil
      }
    } message: { root in
      Text(
        "Nivlo will remove \(root.displayName) from the local index and stop watching it. Original files stay untouched in Finder."
      )
    }
  }

  private var sidebar: some View {
    List(selection: $selection) {
      Section("Library") {
        Label("All Images", systemImage: "photo.on.rectangle.angled")
          .badge(model.assets.count)
          .tag(SectionSelection.allImages)
        Label("Mac Spotlight Discovery", systemImage: "sparkle.magnifyingglass")
          .badge(model.spotlightCandidates.count)
          .tag(SectionSelection.spotlight)
        Label("Duplicates", systemImage: "square.on.square")
          .badge(model.duplicateGroups.count)
          .tag(SectionSelection.duplicates)
        Label("Similar", systemImage: "circle.grid.cross")
          .badge(model.similarGroups.count)
          .tag(SectionSelection.similar)
      }
      Section("Smart Views") {
        smartViewRow(.screenshots, systemImage: "camera.viewfinder")
        smartViewRow(.recentDownloads, systemImage: "arrow.down.circle")
        smartViewRow(.recentlyModified, systemImage: "clock.arrow.circlepath")
        smartViewRow(.largeFiles, systemImage: "externaldrive.badge.icloud")
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
        Label(
          model.validationStatusMessage,
          systemImage: "checkmark.shield"
        )
        Label(
          model.processingStatusMessage,
          systemImage: "square.and.arrow.up"
        )
      }
      if !model.roots.isEmpty {
        Section("Folders") {
          Button {
            Task {
              await model.validateLibraryNow()
            }
          } label: {
            Label("Validate Index", systemImage: "checkmark.shield")
          }
          .buttonStyle(.plain)
          ForEach(model.roots) { root in
            FolderSidebarRow(
              root: root,
              onRescan: {
                Task {
                  await model.rescan(root)
                }
              },
              onRemove: {
                folderPendingRemoval = root
              }
            )
          }
        }
      }
    }
    .navigationSplitViewColumnWidth(min: 210, ideal: 240)
  }

  private func smartViewRow(
    _ smartView: SmartAssetView,
    systemImage: String
  ) -> some View {
    Label(smartView.title, systemImage: systemImage)
      .badge(model.smartAssets(smartView, query: AssetQuery()).count)
      .tag(SectionSelection.smart(smartView))
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
    } else if case .smart(let smartView) = selection {
      assetGridContent(
        title: smartView.title,
        assets: model.smartAssets(smartView, query: currentQuery),
        emptyTitle: "No \(smartView.title)",
        emptyDescription: "Nivlo will show matching indexed images here."
      )
    } else if model.assets.isEmpty {
      ContentUnavailableView {
        Label("Your visual library starts here", systemImage: "photo.stack")
      } description: {
        Text("Add a folder. Nivlo indexes images in place and never uploads the originals.")
      } actions: {
        Button("Add Folder") {
          chooseFolderToIndex()
        }
        .buttonStyle(.borderedProminent)
      }
    } else {
      assetGridContent(
        title: "All Images",
        assets: model.filteredAssets(query: currentQuery),
        emptyTitle: "No Matching Images",
        emptyDescription: "Try a different filename, path, OCR text, or keyword."
      )
    }
  }

  private var currentQuery: AssetQuery {
    let timeBounds = timeFilter.bounds(now: Date())
    return AssetQuery(
      searchText: searchText,
      folders: folderFilter.map { [URL(filePath: $0)] } ?? [],
      contentTypes: formatFilter.contentTypes,
      minimumFileSize: sizeFilter.minimumFileSize,
      minimumPixelWidth: dimensionFilter.minimumPixelWidth,
      minimumPixelHeight: dimensionFilter.minimumPixelHeight,
      createdAfter: timeBounds.createdAfter,
      modifiedAfter: timeBounds.modifiedAfter,
      sources: sourceFilter.map { Set([$0]) } ?? [],
      sort: sortOption.assetSort
    )
  }

  @ViewBuilder
  private func assetGridContent(
    title: String,
    assets: [ImageAsset],
    emptyTitle: String,
    emptyDescription: String
  ) -> some View {
    if assets.isEmpty {
      ContentUnavailableView(
        emptyTitle,
        systemImage: "photo.stack",
        description: Text(emptyDescription)
      )
      .navigationTitle(title)
    } else {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(assets) { asset in
            AssetCard(
              asset: asset,
              enrichment: model.enrichments[asset.id],
              isSelected: selectedAssetIDs.contains(asset.id)
            )
            .onTapGesture {
              previewAsset = asset
            }
          }
        }
        .padding(24)
      }
      .navigationTitle(title)
    }
  }

  private func toggleSelection(_ assetID: AssetID) {
    if selectedAssetIDs.contains(assetID) {
      selectedAssetIDs.remove(assetID)
    } else {
      selectedAssetIDs.insert(assetID)
    }
  }

  private func chooseFolderToIndex() {
    guard
      let url = chooseDirectory(
        title: "Add Folder to Nivlo",
        prompt: "Add Folder"
      )
    else {
      return
    }
    Task {
      await model.addFolder(url)
    }
  }

  private func removeFolder(_ root: LibraryRoot) {
    if folderFilter == root.pathHint {
      folderFilter = nil
    }
    selectedAssetIDs = selectedAssetIDs.filter { assetID in
      model.assets.contains { asset in
        asset.id == assetID && !asset.url.isContained(in: URL(filePath: root.pathHint))
      }
    }
    if previewAsset?.url.isContained(in: URL(filePath: root.pathHint)) == true {
      previewAsset = nil
    }
    folderPendingRemoval = nil
    Task {
      await model.removeFolder(root)
    }
  }

  private func chooseExportFolder() {
    chooseExportFolder(assetIDs: selectedAssetIDs)
  }

  private func chooseExportFolder(assetIDs: Set<AssetID>) {
    guard
      let url = chooseDirectory(
        title: "Export Selected Images",
        prompt: "Export"
      )
    else {
      return
    }
    Task {
      await model.exportAssets(assetIDs: assetIDs, to: url)
      selectedAssetIDs.subtract(assetIDs)
    }
  }

  private func chooseDirectory(
    title: String,
    prompt: String
  ) -> URL? {
    let panel = NSOpenPanel()
    panel.title = title
    panel.prompt = prompt
    panel.canChooseFiles = false
    panel.canChooseDirectories = true
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    return panel.runModal() == .OK ? panel.url : nil
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
                    enrichment: model.enrichments[asset.id],
                    isSelected: selectedAssetIDs.contains(asset.id)
                  )
                  .onTapGesture {
                    previewAsset = asset
                  }
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
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        SpotlightExplainerCard(
          isDiscovering: model.isDiscoveringSpotlight,
          statusMessage: model.spotlightStatusMessage,
          onAddFolder: chooseFolderToIndex
        )

        if !model.spotlightCandidates.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text("Suggested local images")
              .font(.headline)
            Text(
              "Pick a suggestion to add its containing folder to Nivlo’s own index."
            )
            .font(.callout)
            .foregroundStyle(.secondary)
          }

          LazyVGrid(columns: columns, spacing: 20) {
            ForEach(model.spotlightCandidates) { candidate in
              SpotlightCandidateCard(candidate: candidate) {
                Task {
                  await model.addFolder(candidate.url.deletingLastPathComponent())
                  await MainActor.run {
                    selection = .allImages
                  }
                }
              }
            }
          }
        } else if model.isDiscoveringSpotlight {
          ProgressView("Finding images already indexed by macOS…")
            .frame(maxWidth: .infinity, minHeight: 160)
        } else {
          ContentUnavailableView(
            "No Spotlight suggestions yet",
            systemImage: "sparkle.magnifyingglass",
            description: Text(
              "This only means macOS did not return candidates to Nivlo. Direct folder indexing still works."
            )
          )
        }
      }
      .padding(24)
    }
    .navigationTitle("Mac Spotlight Discovery")
  }
}

private struct SpotlightExplainerCard: View {
  let isDiscovering: Bool
  let statusMessage: String
  let onAddFolder: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "sparkle.magnifyingglass")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(.tint)
          .frame(width: 38)

        VStack(alignment: .leading, spacing: 8) {
          Text("Spotlight is only a discovery shortcut")
            .font(.title3.weight(.semibold))
          Text(
            "Nivlo asks macOS Spotlight for images the system already knows about, then lets you add the containing folders to Nivlo’s own local index. Spotlight is not the source of truth and it is not limited to folders you already added."
          )
          .font(.callout)
          .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 10) {
        Label(
          isDiscovering ? "Discovering…" : statusMessage,
          systemImage: isDiscovering ? "hourglass" : "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer()

        Button("Add Folder Directly") {
          onAddFolder()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(18)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 18))
  }
}

private struct SpotlightCandidateCard: View {
  let candidate: SpotlightCandidate
  let onAddFolder: () -> Void

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
      Button("Add Containing Folder") {
        onAddFolder()
      }
      .buttonStyle(.bordered)
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    .contextMenu {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
      }
      Button("Copy Path") {
        AssetClipboard.copyPath(candidate.url)
      }
    }
  }
}

private struct FolderSidebarRow: View {
  let root: LibraryRoot
  let onRescan: () -> Void
  let onRemove: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button(action: onRescan) {
        Label(root.displayName, systemImage: "folder")
          .lineLimit(1)
      }
      .buttonStyle(.plain)

      Spacer(minLength: 4)

      Menu {
        Button("Rescan Folder") {
          onRescan()
        }
        Button("Show in Finder") {
          NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: root.pathHint)])
        }
        Divider()
        Button("Remove from Nivlo", role: .destructive) {
          onRemove()
        }
      } label: {
        Image(systemName: "ellipsis.circle")
          .imageScale(.small)
          .foregroundStyle(.secondary)
      }
      .menuStyle(.borderlessButton)
      .fixedSize()
    }
    .contextMenu {
      Button("Rescan Folder") {
        onRescan()
      }
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([URL(filePath: root.pathHint)])
      }
      Button("Remove from Nivlo", role: .destructive) {
        onRemove()
      }
    }
  }
}

private struct AssetCard: View {
  let asset: ImageAsset
  let enrichment: AssetEnrichment?
  var isSelected = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack(alignment: .topTrailing) {
        thumbnail
          .aspectRatio(4 / 3, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .contentShape(RoundedRectangle(cornerRadius: 12))
        if isSelected {
          Image(systemName: "checkmark.circle.fill")
            .font(.title2)
            .symbolRenderingMode(.palette)
            .foregroundStyle(.white, Color.accentColor)
            .padding(8)
        }
      }
      Text(asset.filename)
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.middle)
        .frame(maxWidth: .infinity, alignment: .leading)
      HStack(spacing: 8) {
        Text(asset.contentType.components(separatedBy: ".").last?.uppercased() ?? "IMAGE")
          .lineLimit(1)
        Spacer()
        if let width = asset.pixelWidth, let height = asset.pixelHeight {
          Text("\(width) × \(height)")
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
      }
      .font(.caption)
      .foregroundStyle(.secondary)
      .frame(maxWidth: .infinity)
    }
    .padding(10)
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
    }
    .contentShape(RoundedRectangle(cornerRadius: 16))
    .draggable(asset.url)
    .contextMenu {
      Button("Show in Finder") {
        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
      }
      Button("Copy Path") {
        AssetClipboard.copyPath(asset.url)
      }
      Button("Copy Markdown Image") {
        AssetClipboard.copyMarkdownImage(asset)
      }
    }
  }

  @ViewBuilder
  private var thumbnail: some View {
    AssetImageView(
      asset: asset,
      enrichment: enrichment,
      maxPixelSize: 420
    )
  }
}

private struct AssetPreviewPanel: View {
  let asset: ImageAsset
  let enrichment: AssetEnrichment?
  let isSelected: Bool
  let onToggleSelection: () -> Void
  let onExport: () -> Void

  @Environment(\.dismiss) private var dismiss

  private var details: AssetPreviewDetails {
    AssetPreviewDetails(asset: asset)
  }

  var body: some View {
    VStack(spacing: 0) {
      HStack(spacing: 12) {
        VStack(alignment: .leading, spacing: 4) {
          Text(details.title)
            .font(.title2.weight(.semibold))
            .lineLimit(1)
          Text(details.path)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        Spacer()

        AssetPreviewToolbar(
          asset: asset,
          isSelected: isSelected,
          onToggleSelection: onToggleSelection,
          onExport: onExport
        )

        Button {
          dismiss()
        } label: {
          Image(systemName: "xmark")
        }
        .buttonStyle(.bordered)
        .keyboardShortcut(.cancelAction)
        .help("Close")
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 14)

      Divider()

      HStack(spacing: 0) {
        ZStack {
          Color(nsColor: .windowBackgroundColor)
          AssetImageView(
            asset: asset,
            enrichment: enrichment,
            maxPixelSize: 1400,
            contentMode: .fit
          )
          .padding(18)
        }
        .frame(minWidth: 700, minHeight: 540)

        Divider()

        VStack(alignment: .leading, spacing: 14) {
          Text("Inspector")
            .font(.headline)
          detailRow("Format", details.format)
          detailRow("Dimensions", details.dimensions)
          detailRow("Size", details.fileSize)
          detailRow("Path", details.path)

          Spacer()
        }
        .padding(18)
        .frame(width: 248)
      }
    }
    .frame(minWidth: 1_020, minHeight: 680)
  }

  private func detailRow(_ label: String, _ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(label)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      Text(value)
        .font(.callout)
        .textSelection(.enabled)
        .lineLimit(label == "Path" ? 3 : 1)
    }
  }
}

private struct AssetPreviewToolbar: View {
  let asset: ImageAsset
  let isSelected: Bool
  let onToggleSelection: () -> Void
  let onExport: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button {
        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
      } label: {
        Label("Finder", systemImage: "finder")
      }
      .help("Show in Finder")

      Button {
        onExport()
      } label: {
        Label("Export", systemImage: "square.and.arrow.up")
      }
      .help("Export image")

      Button {
        onToggleSelection()
      } label: {
        Label(
          isSelected ? "Selected" : "Select",
          systemImage: isSelected ? "checkmark.circle.fill" : "circle"
        )
      }
      .help(isSelected ? "Remove from export selection" : "Select for export")

      Menu {
        Button("Copy Path") {
          AssetClipboard.copyPath(asset.url)
        }
        Button("Copy Markdown Image") {
          AssetClipboard.copyMarkdownImage(asset)
        }
      } label: {
        Label("Copy", systemImage: "doc.on.doc")
      }
      .help("Copy path or Markdown image reference")
    }
    .buttonStyle(.bordered)
  }
}

private enum AssetClipboard {
  static func copyPath(_ url: URL) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(url.standardizedFileURL.path, forType: .string)
  }

  static func copyMarkdownImage(_ asset: ImageAsset) {
    let altText = asset.filename
      .replacingOccurrences(of: "[", with: "\\[")
      .replacingOccurrences(of: "]", with: "\\]")
    let path = asset.url.standardizedFileURL.path
      .replacingOccurrences(of: ">", with: "%3E")
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString("![\(altText)](<\(path)>)", forType: .string)
  }
}

extension URL {
  fileprivate func isContained(in rootURL: URL) -> Bool {
    let candidatePath = standardizedFileURL.path
    let rootPath = rootURL.standardizedFileURL.path
    return candidatePath == rootPath
      || candidatePath.hasPrefix(rootPath + "/")
  }
}

private enum SortOption: String, CaseIterable, Identifiable {
  case path
  case filename
  case newestModified
  case oldestModified
  case largest
  case dimensions
  case source

  var id: String { rawValue }

  var title: String {
    switch self {
    case .path:
      "Path"
    case .filename:
      "Filename"
    case .newestModified:
      "Newest Modified"
    case .oldestModified:
      "Oldest Modified"
    case .largest:
      "Largest"
    case .dimensions:
      "Dimensions"
    case .source:
      "Source"
    }
  }

  var assetSort: AssetSort {
    switch self {
    case .path:
      .path(order: .ascending)
    case .filename:
      .filename(order: .ascending)
    case .newestModified:
      .modifiedAt(order: .descending)
    case .oldestModified:
      .modifiedAt(order: .ascending)
    case .largest:
      .fileSize(order: .descending)
    case .dimensions:
      .dimensions(order: .descending)
    case .source:
      .source(order: .ascending)
    }
  }
}

private enum FormatFilter: String, CaseIterable, Identifiable {
  case all
  case png
  case jpeg
  case webp
  case avif

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all:
      "All Formats"
    case .png:
      "PNG"
    case .jpeg:
      "JPEG"
    case .webp:
      "WebP"
    case .avif:
      "AVIF"
    }
  }

  var contentTypes: Set<String> {
    switch self {
    case .all:
      []
    case .png:
      ["public.png"]
    case .jpeg:
      ["public.jpeg"]
    case .webp:
      ["org.webmproject.webp"]
    case .avif:
      ["public.avif"]
    }
  }
}

private enum TimeFilter: String, CaseIterable, Identifiable {
  case all
  case createdLast14Days
  case modifiedLast14Days

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all:
      "Any Time"
    case .createdLast14Days:
      "Created Last 14 Days"
    case .modifiedLast14Days:
      "Modified Last 14 Days"
    }
  }

  func bounds(now: Date) -> (createdAfter: Date?, modifiedAfter: Date?) {
    let threshold = now.addingTimeInterval(-14 * 24 * 60 * 60)
    switch self {
    case .all:
      return (nil, nil)
    case .createdLast14Days:
      return (threshold, nil)
    case .modifiedLast14Days:
      return (nil, threshold)
    }
  }
}

private enum SizeFilter: String, CaseIterable, Identifiable {
  case all
  case atLeastOneMB
  case large

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all:
      "Any Size"
    case .atLeastOneMB:
      "At Least 1 MB"
    case .large:
      "Large Files"
    }
  }

  var minimumFileSize: Int64? {
    switch self {
    case .all:
      nil
    case .atLeastOneMB:
      1_000_000
    case .large:
      50_000_000
    }
  }
}

private enum DimensionFilter: String, CaseIterable, Identifiable {
  case all
  case atLeastHD
  case atLeast4K

  var id: String { rawValue }

  var title: String {
    switch self {
    case .all:
      "Any Dimensions"
    case .atLeastHD:
      "At Least HD"
    case .atLeast4K:
      "At Least 4K"
    }
  }

  var minimumPixelWidth: Int? {
    switch self {
    case .all:
      nil
    case .atLeastHD:
      1280
    case .atLeast4K:
      3840
    }
  }

  var minimumPixelHeight: Int? {
    switch self {
    case .all:
      nil
    case .atLeastHD:
      720
    case .atLeast4K:
      2160
    }
  }
}

extension AssetSource {
  fileprivate var title: String {
    switch self {
    case .desktop:
      "Desktop"
    case .downloads:
      "Downloads"
    case .documents:
      "Documents"
    case .externalVolume:
      "External Volume"
    case .project:
      "Project"
    case .other:
      "Other"
    }
  }
}
