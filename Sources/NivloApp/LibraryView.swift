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
  @State private var isChoosingFolder = false
  @State private var isChoosingExportFolder = false
  @State private var selection: SectionSelection? = .allImages
  @State private var searchText = ""
  @State private var selectedAssetIDs: Set<AssetID> = []
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
          isChoosingFolder = true
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
          isChoosingExportFolder = true
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
    .fileImporter(
      isPresented: $isChoosingExportFolder,
      allowedContentTypes: [.folder],
      allowsMultipleSelection: false
    ) { result in
      guard case .success(let urls) = result, let url = urls.first else {
        return
      }
      Task {
        await model.exportAssets(assetIDs: selectedAssetIDs, to: url)
        selectedAssetIDs = []
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
          isChoosingFolder = true
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
              toggleSelection(asset.id)
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
  var isSelected = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack(alignment: .topTrailing) {
        thumbnail
          .aspectRatio(4 / 3, contentMode: .fit)
          .clipShape(RoundedRectangle(cornerRadius: 12))
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
    .overlay {
      RoundedRectangle(cornerRadius: 16)
        .stroke(isSelected ? Color.accentColor : .clear, lineWidth: 3)
    }
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
          "![\(altText)](<\(asset.url.path.replacingOccurrences(of: ">", with: "%3E"))>)",
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
