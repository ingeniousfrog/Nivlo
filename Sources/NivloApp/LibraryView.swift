import AppKit
import NivloDomain
import NivloImaging
import NivloIndexing
import SwiftUI
import UniformTypeIdentifiers

enum NivloLanguage: String, CaseIterable, Identifiable {
  case english
  case simplifiedChinese

  var id: String { rawValue }

  var displayName: String {
    switch self {
    case .english:
      "English"
    case .simplifiedChinese:
      "简体中文"
    }
  }

  var addFolder: String { text("Add Folder", "添加文件夹") }
  var allImages: String { text("All Images", "全部图片") }
  var cancel: String { text("Cancel", "取消") }
  var hideAsset: String { text("Hide", "隐藏") }
  var hideHelp: String {
    text("Hide from Nivlo without deleting the original file", "从 Nivlo 隐藏，但不删除原文件")
  }
  var dimensions: String { text("Dimensions", "尺寸") }
  var duplicates: String { text("Duplicates", "重复项") }
  var edit: String { text("Edit", "编辑") }
  var editHelp: String { text("Open this asset for editing", "打开此素材进行编辑") }
  var emptyLibraryDescription: String {
    text(
      "Add a folder. Nivlo indexes images in place and never uploads the originals.",
      "添加文件夹后，Nivlo 会就地索引图片，不移动、不上传原文件。"
    )
  }
  var emptyLibraryTitle: String { text("Your visual library starts here", "从这里开始建立视觉素材库") }
  var export: String { text("Export", "导出") }
  var exportAsset: String { text("Export image", "导出图片") }
  var exportSelected: String { text("Export Selected", "导出所选") }
  var filter: String { text("Filter", "筛选") }
  var finder: String { text("Finder", "访达") }
  var folders: String { text("Folders", "文件夹") }
  var format: String { text("Format", "格式") }
  var hide: String { text("Hide", "隐藏") }
  var hiddenFiles: String { text("Hidden Files", "隐藏文件") }
  var hiddenFilesDescription: String {
    text("Assets hidden from the main library appear here.", "从主图库隐藏的素材会显示在这里。")
  }
  var noHiddenFiles: String { text("No Hidden Files", "没有隐藏文件") }
  var restore: String { text("Unhide", "取消隐藏") }
  var hideAssetTitle: String { text("Hide asset from Nivlo?", "从 Nivlo 隐藏这个素材？") }
  var inspector: String { text("Inspector", "信息") }
  var library: String { text("Library", "图库") }
  var noMatchingDescription: String {
    text(
      "Try a different filename, path, OCR text, or keyword.",
      "试试其他文件名、路径、OCR 文本或关键词。"
    )
  }
  var noMatchingImages: String { text("No Matching Images", "没有匹配图片") }
  var noSmartViewDescription: String {
    text(
      "Nivlo will show matching indexed images here.",
      "Nivlo 会在这里显示匹配的已索引图片。"
    )
  }
  var path: String { text("Path", "路径") }
  var remove: String { text("Remove", "移除") }
  var removeFolderTitle: String { text("Remove folder from Nivlo?", "从 Nivlo 移除此文件夹？") }
  var removeFromSelection: String { text("Remove from export selection", "从导出选择中移除") }
  var searchPrompt: String { text("Search filename, path, OCR, keywords", "搜索文件名、路径、OCR、关键词") }
  var select: String { text("Select", "选择") }
  var selected: String { text("Selected", "已选择") }
  var selectForExport: String { text("Select for export", "选择用于导出") }
  var showInFinder: String { text("Show in Finder", "在访达中显示") }
  var similar: String { text("Similar", "相似图片") }
  var size: String { text("Size", "大小") }
  var smartViews: String { text("Smart Views", "智能视图") }
  var explore: String { text("Explore", "探索") }
  var exploreTitle: String { text("Explore local images", "探索本地图片") }
  var exploreDescription: String {
    text(
      "Nivlo uses the image index already maintained by macOS to quickly suggest local folders. Nothing is uploaded, and folders are indexed only after you choose to add them.",
      "Nivlo 会利用 macOS 已维护的图片索引，快速发现本机可能包含素材的文件夹。图片不会上传，只有你主动添加的文件夹才会进入 Nivlo 索引。"
    )
  }
  var exploreSuggestedImages: String { text("Suggested local images", "建议的本地图片") }
  var exploreSuggestionDescription: String {
    text(
      "Choose an image to add its containing folder to Nivlo.",
      "选择一张图片，将它所在的文件夹添加到 Nivlo。"
    )
  }
  var addFolderDirectly: String { text("Add Folder Directly", "直接添加文件夹") }
  var addContainingFolder: String { text("Add Containing Folder", "添加所在文件夹") }
  var findingLocalImages: String {
    text("Finding images already indexed by macOS…", "正在查找 macOS 已索引的图片…")
  }
  var noExploreSuggestions: String { text("No suggestions yet", "暂无探索建议") }
  var noExploreSuggestionsDescription: String {
    text(
      "macOS did not return any indexed images. You can still add folders directly.",
      "macOS 暂未返回已索引图片，你仍然可以直接添加文件夹。"
    )
  }
  var exploreUnavailable: String { text("Explore unavailable", "探索暂不可用") }
  var exploreUnavailableDescription: String {
    text(
      "Spotlight could not start. Check that Spotlight indexing is enabled, then try again. Installing Nivlo is not required.",
      "Spotlight 查询无法启动。请确认系统已开启 Spotlight 索引后重试；无需先安装 Nivlo。"
    )
  }
  var discovering: String { text("Discovering…", "正在探索…") }
  var status: String { text("Status", "状态") }
  var validateIndex: String { text("Validate Index", "校验索引") }
  var copyPath: String { text("Copy path", "复制路径") }
  var copied: String { text("Copied", "已复制") }
  var copyFailed: String { text("Copy failed", "复制失败") }
  var close: String { text("Close", "关闭") }
  var editorTitle: String { text("Nivlo Editor", "Nivlo 编辑器") }
  var flipHorizontal: String { text("Flip Horizontal", "水平翻转") }
  var reset: String { text("Reset", "重置") }
  var rotateLeft: String { text("Rotate Left", "向左旋转") }
  var rotateRight: String { text("Rotate Right", "向右旋转") }
  var saveEditedCopy: String { text("Export Edited Copy", "导出编辑副本") }
  var editorExported: String { text("Edited copy exported", "编辑副本已导出") }
  var editorExportFailed: String { text("Couldn’t export edited copy", "无法导出编辑副本") }
  var originalFileProtected: String {
    text(
      "Choose a different filename. Nivlo never overwrites the original file.",
      "请选择其他文件名。Nivlo 不会覆盖原文件。"
    )
  }
  var videoEditorTitle: String { text("Nivlo Video Editor", "Nivlo 视频编辑器") }
  var trimVideo: String { text("Trim Video", "裁剪视频") }
  var trimStart: String { text("Start", "开始") }
  var trimEnd: String { text("End", "结束") }
  var exportTrimmedVideo: String { text("Export Trimmed Video", "导出裁剪视频") }
  var exportingVideo: String { text("Exporting video…", "正在导出视频…") }
  var videoExported: String { text("Trimmed video exported", "裁剪视频已导出") }
  var videoExportFailed: String { text("Couldn’t export video", "无法导出视频") }
  var videoPreviewUnavailable: String { text("Video preview unavailable", "视频无法预览") }
  var toolsStatusTitle: String { text("Processing tools", "处理工具") }
  var toolsNotReady: String { text("Tools are still installing", "工具仍在安装中") }
  var retry: String { text("Retry", "重试") }
  var tabGeometry: String { text("Geometry", "几何") }
  var tabAdjust: String { text("Adjust", "调整") }
  var tabAnnotate: String { text("Annotate", "标注") }
  var tabMask: String { text("Mask", "蒙版") }
  var tabExport: String { text("Export", "导出") }
  var tabTransform: String { text("Transform", "形变") }
  var tabLineage: String { text("Lineage", "谱系") }
  var tabAI: String { text("AI", "AI") }
  var adjustExposure: String { text("Exposure", "曝光") }
  var adjustContrast: String { text("Contrast", "对比度") }
  var adjustSaturation: String { text("Saturation", "饱和度") }
  var adjustWarmth: String { text("Warmth", "色温") }
  var addTextAnnotation: String { text("Add text", "添加文字") }
  var addRectangleAnnotation: String { text("Add rectangle", "添加矩形") }
  var addArrowAnnotation: String { text("Add arrow", "添加箭头") }
  var clearAnnotations: String { text("Clear annotations", "清除标注") }
  var annotationCount: String { text("Annotations", "标注数") }
  var addMaskStroke: String { text("Add mask brush", "添加蒙版笔触") }
  var clearMask: String { text("Clear mask", "清除蒙版") }
  var maskStrokeCount: String { text("Mask strokes", "蒙版笔触数") }
  var layerBackground: String { text("Background layer", "背景层") }
  var layerAdjustments: String { text("Adjustments layer", "调整层") }
  var layerAnnotations: String { text("Annotations layer", "标注层") }
  var layerMask: String { text("Mask layer", "蒙版层") }
  var exportFormat: String { text("Format", "格式") }
  var exportPreset: String { text("Preset", "预设") }
  var exportQuality: String { text("Quality", "质量") }
  var maxWidth: String { text("Max width", "最大宽度") }
  var maxHeight: String { text("Max height", "最大高度") }
  var targetSizeKB: String { text("Target size (KB)", "目标大小 (KB)") }
  var cropX: String { text("Crop X", "裁切 X") }
  var cropY: String { text("Crop Y", "裁切 Y") }
  var cropWidth: String { text("Crop width", "裁切宽度") }
  var cropHeight: String { text("Crop height", "裁切高度") }
  var scaleWidth: String { text("Scale width", "缩放宽度") }
  var scaleHeight: String { text("Scale height", "缩放高度") }
  var rotateVideo: String { text("Rotate (90° steps)", "旋转 (90°)") }
  var outputFPS: String { text("Output FPS", "输出帧率") }
  var videoCRF: String { text("CRF", "CRF") }
  var extractAudioOnly: String { text("Extract audio only", "仅提取音频") }
  var audioFormat: String { text("Audio format", "音频格式") }
  var noLineageTitle: String { text("No derivatives yet", "尚无衍生文件") }
  var noLineageDescription: String {
    text(
      "Exports, edits, and AI generations for this asset will appear here.",
      "此素材的导出、编辑和 AI 生成记录会显示在这里。"
    )
  }
  var aiProvider: String { text("Provider", "提供方") }
  var aiAPIKey: String { text("API key", "API 密钥") }
  var aiCapability: String { text("Capability", "能力") }
  var aiPrompt: String { text("Prompt", "提示词") }
  var aiNegativePrompt: String { text("Negative prompt", "反向提示词") }
  var aiStrength: String { text("Strength", "强度") }
  var aiSteps: String { text("Steps", "步数") }
  var aiGenerate: String { text("Generate", "生成") }
  var aiGenerating: String { text("Generating…", "正在生成…") }
  var aiGenerated: String { text("Generation complete", "生成完成") }
  var saveAPIKey: String { text("Save API key", "保存 API 密钥") }
  var apiKeySaved: String { text("API key saved", "API 密钥已保存") }
  var editorCanvasHint: String {
    text("Edits are previewed live. Export writes a new file without changing the original.", "编辑会实时预览。导出会写入新文件，不会修改原图。")
  }
  var editorGeometryHint: String {
    text(
      "Drag handles or edges to crop. Use Apply to commit, Preview to check the result.",
      "拖动手柄或边缘进行裁切。Apply 提交，Preview 预览效果。"
    )
  }
  var editorAdjustHint: String {
    text(
      "Tune sliders, then Preview or Apply. Revert restores the last applied values.",
      "调节滑块后可 Preview 或 Apply。Revert 恢复上次已提交的值。"
    )
  }
  var maskBrushHint: String {
    text(
      "Paint on the image to keep areas. Unpainted regions become transparent on export.",
      "在图像上涂抹要保留的区域；未涂抹部分导出时变为透明。"
    )
  }
  var maskBrushSize: String { text("Brush size", "画笔大小") }
  var applyChanges: String { text("Apply", "应用") }
  var previewChanges: String { text("Preview", "预览") }
  var revertChanges: String { text("Revert", "还原") }
  var changesApplied: String { text("Changes applied", "更改已应用") }
  var previewActive: String { text("Previewing", "预览中") }
  var previewActiveHint: String {
    text("Showing rendered preview. Exit preview to keep editing.", "正在显示渲染预览。退出预览后可继续编辑。")
  }
  var exitPreview: String { text("Exit preview", "退出预览") }
  var renderingPreview: String { text("Rendering preview…", "正在生成预览…") }
  var previewFailed: String { text("Preview failed", "预览失败") }
  var cropSizeLabel: String { text("Crop size", "裁切区域") }
  var exportingImage: String { text("Exporting image…", "正在导出图片…") }
  var exportAudioOnly: String { text("Export Audio", "导出音频") }
  var exportingAudio: String { text("Exporting audio…", "正在导出音频…") }
  var audioExported: String { text("Audio exported", "音频已导出") }
  var audioExtractDescription: String {
    text(
      "Exports only the audio track from the trimmed range. The original video file is not modified.",
      "仅导出所选时间范围内的音轨，不会修改原视频文件。"
    )
  }
  var audioExportHint: String {
    text("Choose Export → Extract audio only, then pick a save location.", "在「导出」中勾选「仅提取音频」，再选择保存位置。")
  }
  var videoExportHint: String {
    text("Trim, transform, and export settings apply to a new output file.", "裁剪、形变与导出设置会写入新的输出文件。")
  }
  var exportReadyTitle: String { text("Export ready", "导出完成") }
  var openExportedFile: String { text("Open file", "打开文件") }
  var trimRangeLabel: String { text("Trim range", "裁剪范围") }

  func hideAssetMessage(_ filename: String) -> String {
    text(
      "Nivlo will hide \(filename) from this app and keep the original file untouched in Finder.",
      "Nivlo 会在本应用中隐藏 \(filename)，但不会修改或删除访达中的原文件。"
    )
  }

  func spotlightStatus(_ state: LibraryModel.SpotlightDiscoveryState) -> String {
    switch state {
    case .checking:
      discovering
    case .ready(let candidateCount):
      candidateCount == 0
        ? text("No suggestions", "暂无建议")
        : text("\(candidateCount) suggestions", "\(candidateCount) 条建议")
    case .unavailable(let reason):
      text("Explore unavailable: \(reason)", "探索暂不可用")
    }
  }

  func exploreFailureDescription(_ reason: String) -> String {
    text(
      "\(exploreUnavailableDescription)\n\nSystem detail: \(reason)",
      exploreUnavailableDescription
    )
  }

  func noSmartViewTitle(_ smartView: SmartAssetView) -> String {
    text("No \(smartView.title)", "没有\(smartViewTitle(smartView))")
  }

  func removeFolderMessage(_ folderName: String) -> String {
    text(
      "Nivlo will remove \(folderName) from the local index and stop watching it. Original files stay untouched in Finder.",
      "Nivlo 会从本地索引中移除 \(folderName) 并停止监听。访达中的原文件不会被修改或删除。"
    )
  }

  func smartViewTitle(_ smartView: SmartAssetView) -> String {
    switch (self, smartView) {
    case (.english, _):
      smartView.title
    case (.simplifiedChinese, .screenshots):
      "截图"
    case (.simplifiedChinese, .recentDownloads):
      "最近下载"
    case (.simplifiedChinese, .recentlyModified):
      "最近修改"
    case (.simplifiedChinese, .largeFiles):
      "大文件"
    }
  }

  private func text(_ english: String, _ chinese: String) -> String {
    switch self {
    case .english:
      english
    case .simplifiedChinese:
      chinese
    }
  }
}

struct LibraryView: View {
  @ObservedObject var toolBootstrapper: ToolBootstrapper

  private enum SectionSelection: Hashable {
    case allImages
    case spotlight
    case duplicates
    case similar
    case hidden
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
  @AppStorage("nivlo.language") private var languageRawValue =
    NivloLanguage.english.rawValue

  private var language: NivloLanguage {
    NivloLanguage(rawValue: languageRawValue) ?? .english
  }

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
          Label(language.addFolder, systemImage: "folder.badge.plus")
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
          Label(language.filter, systemImage: "line.3.horizontal.decrease.circle")
        }
      }
      ToolbarItem {
        Button {
          chooseExportFolder()
        } label: {
          Label(language.exportSelected, systemImage: "square.and.arrow.up")
        }
        .disabled(selectedAssetIDs.isEmpty)
      }
      ToolbarItem {
        Picker("Language", selection: $languageRawValue) {
          ForEach(NivloLanguage.allCases) { language in
            Text(language.displayName).tag(language.rawValue)
          }
        }
        .pickerStyle(.menu)
      }
    }
    .searchable(
      text: $searchText,
      placement: .toolbar,
      prompt: Text(language.searchPrompt)
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
        language: language,
        isSelected: selectedAssetIDs.contains(asset.id),
        toolsReady: model.toolBootstrapper.isReady,
        onToggleSelection: {
          toggleSelection(asset.id)
        },
        onExport: {
          chooseExportFolder(assetIDs: [asset.id])
        },
        onHide: {
          hideAsset(asset)
        },
        onImageExported: { result, request in
          Task {
            await model.recordEditedImageExport(
              asset: asset,
              result: result,
              request: request
            )
          }
        },
        onVideoExported: { outputURL, request in
          Task {
            await model.recordEditedVideoExport(
              asset: asset,
              outputURL: outputURL,
              request: request
            )
          }
        },
        onAIGenerated: { result in
          Task {
            await model.recordAIGeneration(asset: asset, result: result)
          }
        },
        lineageProvider: {
          await model.lineage(for: asset)
        }
      )
    }
    .alert(
      language.removeFolderTitle,
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
      Button(language.remove, role: .destructive) {
        removeFolder(root)
      }
      Button(language.cancel, role: .cancel) {
        folderPendingRemoval = nil
      }
    } message: { root in
      Text(
        language.removeFolderMessage(root.displayName)
      )
    }
  }

  private var sidebar: some View {
    List(selection: $selection) {
      Section(language.library) {
        Label(language.allImages, systemImage: "photo.on.rectangle.angled")
          .badge(model.assets.count)
          .tag(SectionSelection.allImages)
        Label(language.explore, systemImage: "sparkle.magnifyingglass")
          .badge(model.spotlightCandidates.count)
          .tag(SectionSelection.spotlight)
        Label(language.duplicates, systemImage: "square.on.square")
          .badge(model.duplicateGroups.count)
          .tag(SectionSelection.duplicates)
        Label(language.similar, systemImage: "circle.grid.cross")
          .badge(model.similarGroups.count)
          .tag(SectionSelection.similar)
        Label(language.hiddenFiles, systemImage: "eye.slash")
          .badge(model.hiddenAssets.count)
          .tag(SectionSelection.hidden)
      }
      Section(language.smartViews) {
        smartViewRow(.screenshots, systemImage: "camera.viewfinder")
        smartViewRow(.recentDownloads, systemImage: "arrow.down.circle")
        smartViewRow(.recentlyModified, systemImage: "clock.arrow.circlepath")
        smartViewRow(.largeFiles, systemImage: "externaldrive.badge.icloud")
      }
      if !model.roots.isEmpty {
        Section(language.folders) {
          Button {
            Task {
              await model.validateLibraryNow()
            }
          } label: {
            Label(language.validateIndex, systemImage: "checkmark.shield")
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
      Section(language.status) {
        Label(
          model.statusMessage,
          systemImage: model.isScanning
            ? "arrow.triangle.2.circlepath"
            : "checkmark.circle"
        )
        Label(
          language.spotlightStatus(model.spotlightDiscoveryState),
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
      Section(language.toolsStatusTitle) {
        ToolHealthView(bootstrapper: toolBootstrapper, language: language, compact: true)
      }
    }
    .navigationSplitViewColumnWidth(min: 210, ideal: 240)
  }

  private func smartViewRow(
    _ smartView: SmartAssetView,
    systemImage: String
  ) -> some View {
    Label(language.smartViewTitle(smartView), systemImage: systemImage)
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
    } else if selection == .hidden {
      hiddenAssetsContent
    } else if case .smart(let smartView) = selection {
      assetGridContent(
        title: language.smartViewTitle(smartView),
        assets: model.smartAssets(smartView, query: currentQuery),
        emptyTitle: language.noSmartViewTitle(smartView),
        emptyDescription: language.noSmartViewDescription
      )
    } else if model.assets.isEmpty {
      ContentUnavailableView {
        Label(language.emptyLibraryTitle, systemImage: "photo.stack")
      } description: {
        Text(language.emptyLibraryDescription)
      } actions: {
        Button(language.addFolder) {
          chooseFolderToIndex()
        }
        .buttonStyle(.borderedProminent)
      }
    } else {
      assetGridContent(
        title: language.allImages,
        assets: model.filteredAssets(query: currentQuery),
        emptyTitle: language.noMatchingImages,
        emptyDescription: language.noMatchingDescription
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
      GeometryReader { proxy in
        ScrollView {
          AssetMasonryGrid(
            assets: assets,
            enrichments: model.enrichments,
            selectedAssetIDs: selectedAssetIDs,
            availableWidth: max(0, proxy.size.width - 48),
            onOpen: { asset in
              previewAsset = asset
            }
          )
          .padding(.horizontal, 24)
          .padding(.top, 20)
          .padding(.bottom, 32)
        }
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

  private func hideAsset(_ asset: ImageAsset) {
    selectedAssetIDs.remove(asset.id)
    if previewAsset?.id == asset.id {
      previewAsset = nil
    }
    Task {
      await model.hideAsset(asset)
    }
  }

  @ViewBuilder
  private var hiddenAssetsContent: some View {
    if model.hiddenAssets.isEmpty {
      ContentUnavailableView(
        language.noHiddenFiles,
        systemImage: "eye.slash",
        description: Text(language.hiddenFilesDescription)
      )
      .navigationTitle(language.hiddenFiles)
    } else {
      ScrollView {
        LazyVGrid(columns: columns, spacing: 20) {
          ForEach(model.hiddenAssets) { record in
            HiddenAssetCard(
              record: record,
              language: language,
              onRestore: {
                Task {
                  if let rootPath = await model.unhideAsset(record) {
                    showRestoredAsset(in: rootPath)
                  }
                }
              }
            )
          }
        }
        .padding(24)
      }
      .navigationTitle(language.hiddenFiles)
    }
  }

  private func showRestoredAsset(in rootPath: String) {
    searchText = ""
    folderFilter = rootPath
    sourceFilter = nil
    formatFilter = .all
    timeFilter = .all
    sizeFilter = .all
    dimensionFilter = .all
    selection = .allImages
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
          state: model.spotlightDiscoveryState,
          language: language,
          onAddFolder: chooseFolderToIndex
        )

        if !model.spotlightCandidates.isEmpty {
          VStack(alignment: .leading, spacing: 8) {
            Text(language.exploreSuggestedImages)
              .font(.headline)
            Text(language.exploreSuggestionDescription)
              .font(.callout)
              .foregroundStyle(.secondary)
          }

          LazyVGrid(columns: columns, spacing: 20) {
            ForEach(model.spotlightCandidates) { candidate in
              SpotlightCandidateCard(candidate: candidate, language: language) {
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
          ProgressView(language.findingLocalImages)
            .frame(maxWidth: .infinity, minHeight: 160)
        } else if case .unavailable(let reason) = model.spotlightDiscoveryState {
          ContentUnavailableView(
            language.exploreUnavailable,
            systemImage: "exclamationmark.magnifyingglass",
            description: Text(language.exploreFailureDescription(reason))
          )
        } else {
          ContentUnavailableView(
            language.noExploreSuggestions,
            systemImage: "sparkle.magnifyingglass",
            description: Text(language.noExploreSuggestionsDescription)
          )
        }
      }
      .padding(24)
    }
    .navigationTitle(language.explore)
  }
}

private struct SpotlightExplainerCard: View {
  let isDiscovering: Bool
  let state: LibraryModel.SpotlightDiscoveryState
  let language: NivloLanguage
  let onAddFolder: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      HStack(alignment: .top, spacing: 12) {
        Image(systemName: "sparkle.magnifyingglass")
          .font(.system(size: 28, weight: .semibold))
          .foregroundStyle(.tint)
          .frame(width: 38)

        VStack(alignment: .leading, spacing: 8) {
          Text(language.exploreTitle)
            .font(.title3.weight(.semibold))
          Text(language.exploreDescription)
            .font(.callout)
            .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 10) {
        Label(
          isDiscovering ? language.discovering : language.spotlightStatus(state),
          systemImage: isDiscovering ? "hourglass" : "info.circle"
        )
        .font(.caption)
        .foregroundStyle(.secondary)

        Spacer()

        Button(language.addFolderDirectly) {
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
  let language: NivloLanguage
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
      Button(language.addContainingFolder) {
        onAddFolder()
      }
      .buttonStyle(.bordered)
    }
    .padding(10)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
    .contextMenu {
      Button(language.showInFinder) {
        NSWorkspace.shared.activateFileViewerSelecting([candidate.url])
      }
      Button(language.copyPath) {
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

struct AssetCard: View {
  let asset: ImageAsset
  let enrichment: AssetEnrichment?
  var isSelected = false

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      ZStack(alignment: .topTrailing) {
        Color.clear
          .aspectRatio(asset.displayAspectRatio, contentMode: .fit)
          .overlay {
            thumbnail
              .scaledToFill()
          }
          .clipShape(RoundedRectangle(cornerRadius: 12))
          .contentShape(RoundedRectangle(cornerRadius: 12))
          .overlay {
            if asset.mediaKind == .video {
              Image(systemName: "play.circle.fill")
                .font(.system(size: 34))
                .symbolRenderingMode(.palette)
                .foregroundStyle(.white, .black.opacity(0.55))
                .allowsHitTesting(false)
            }
          }
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

private struct HiddenAssetCard: View {
  let record: HiddenAssetRecord
  let language: NivloLanguage
  let onRestore: () -> Void

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      if let asset = record.asset {
        AssetImageView(
          asset: asset,
          enrichment: nil,
          maxPixelSize: 420
        )
        .aspectRatio(4 / 3, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 12))
      } else {
        ZStack {
          RoundedRectangle(cornerRadius: 12)
            .fill(.quaternary)
          Image(systemName: "eye.slash")
            .font(.largeTitle)
            .foregroundStyle(.secondary)
        }
        .aspectRatio(4 / 3, contentMode: .fit)
      }

      Text(record.url.lastPathComponent)
        .font(.headline)
        .lineLimit(1)
        .truncationMode(.middle)
      Text(record.url.deletingLastPathComponent().path)
        .font(.caption)
        .foregroundStyle(.secondary)
        .lineLimit(2)
        .truncationMode(.middle)

      HStack {
        Button(language.restore) {
          onRestore()
        }
        .buttonStyle(.borderedProminent)
        Spacer()
        Button {
          NSWorkspace.shared.activateFileViewerSelecting([record.url])
        } label: {
          Image(systemName: "finder")
        }
        .buttonStyle(.bordered)
        .help(language.showInFinder)
      }
    }
    .padding(10)
    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 16))
  }
}

private enum AssetPreviewSidebarTab: String, CaseIterable, Identifiable {
  case inspector
  case lineage
  case ai

  var id: String { rawValue }
}

private struct AssetPreviewPanel: View {
  let asset: ImageAsset
  let enrichment: AssetEnrichment?
  let language: NivloLanguage
  let isSelected: Bool
  let toolsReady: Bool
  let onToggleSelection: () -> Void
  let onExport: () -> Void
  let onHide: () -> Void
  let onImageExported: (PicxOptimizeResult, ImageEditRequest) -> Void
  let onVideoExported: (URL, VideoEditRequest) -> Void
  let onAIGenerated: (GenerationResult) -> Void
  let lineageProvider: () async -> AssetLineageGraph

  @Environment(\.dismiss) private var dismiss
  @State private var isEditorPresented = false
  @State private var isHideConfirmationPresented = false
  @State private var copyFeedback: CopyFeedback?
  @State private var copyFeedbackTask: Task<Void, Never>?
  @State private var sidebarTab: AssetPreviewSidebarTab = .inspector
  @State private var lineageGraph = AssetLineageGraph(assetID: AssetID(volumeIdentifier: "", fileIdentifier: ""), records: [])

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
          language: language,
          isSelected: isSelected,
          onToggleSelection: onToggleSelection,
          onExport: onExport,
          onEdit: {
            isEditorPresented = true
          },
          onHide: {
            isHideConfirmationPresented = true
          }
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
          if asset.mediaKind == .video {
            AssetVideoPlayerView(asset: asset)
              .padding(18)
          } else {
            AssetImageView(
              asset: asset,
              enrichment: enrichment,
              maxPixelSize: 1400,
              contentMode: .fit
            )
            .padding(18)
          }
        }
        .frame(minWidth: 700, minHeight: 540)

        Divider()

        VStack(alignment: .leading, spacing: 14) {
          Picker("Sidebar", selection: $sidebarTab) {
            Text(language.inspector).tag(AssetPreviewSidebarTab.inspector)
            Text(language.tabLineage).tag(AssetPreviewSidebarTab.lineage)
            Text(language.tabAI).tag(AssetPreviewSidebarTab.ai)
          }
          .pickerStyle(.segmented)

          switch sidebarTab {
          case .inspector:
            detailRow(language.format, details.format)
            detailRow(language.dimensions, details.dimensions)
            detailRow(language.size, details.fileSize)
            pathRow(details.path)
          case .lineage:
            LineageView(graph: lineageGraph, language: language)
              .frame(maxWidth: .infinity, maxHeight: .infinity)
          case .ai:
            AIGenerationPanel(
              asset: asset,
              language: language,
              onGenerated: onAIGenerated
            )
          }

          Spacer()
        }
        .padding(18)
        .frame(width: 320)
      }
    }
    .frame(minWidth: 1_080, minHeight: 680)
    .task(id: asset.id) {
      lineageGraph = await lineageProvider()
    }
    .sheet(isPresented: $isEditorPresented) {
      switch asset.mediaKind {
      case .image:
        AssetEditorView(
          asset: asset,
          language: language,
          toolsReady: toolsReady,
          onExport: onImageExported
        )
      case .video:
        VideoEditorView(
          asset: asset,
          language: language,
          toolsReady: toolsReady,
          onExport: onVideoExported
        )
      case .unsupported:
        ContentUnavailableView(
          language.videoPreviewUnavailable,
          systemImage: "questionmark.square.dashed"
        )
        .frame(minWidth: 640, minHeight: 420)
      }
    }
    .alert(
      language.hideAssetTitle,
      isPresented: $isHideConfirmationPresented
    ) {
      Button(language.hide, role: .destructive) {
        onHide()
      }
      Button(language.cancel, role: .cancel) {}
    } message: {
      Text(language.hideAssetMessage(asset.filename))
    }
    .onDisappear {
      copyFeedbackTask?.cancel()
    }
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

  private func pathRow(_ value: String) -> some View {
    VStack(alignment: .leading, spacing: 4) {
      Text(language.path)
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
      HStack(alignment: .top, spacing: 6) {
        Text(value)
          .font(.callout)
          .textSelection(.enabled)
          .lineLimit(4)
        Button {
          copyPath()
        } label: {
          if let copyFeedback {
            Label(
              copyFeedback == .success ? language.copied : language.copyFailed,
              systemImage: copyFeedback == .success
                ? "checkmark.circle.fill"
                : "exclamationmark.circle"
            )
          } else {
            Image(systemName: "doc.on.doc")
          }
        }
        .buttonStyle(.borderless)
        .help(language.copyPath)
      }
    }
  }

  private func copyPath() {
    copyFeedbackTask?.cancel()
    copyFeedback = AssetClipboard.copyPath(asset.url) ? .success : .failure
    copyFeedbackTask = Task {
      do {
        try await Task.sleep(for: .seconds(1.5))
      } catch {
        return
      }
      copyFeedback = nil
    }
  }

  private enum CopyFeedback: Equatable {
    case success
    case failure
  }
}

private struct AssetPreviewToolbar: View {
  let asset: ImageAsset
  let language: NivloLanguage
  let isSelected: Bool
  let onToggleSelection: () -> Void
  let onExport: () -> Void
  let onEdit: () -> Void
  let onHide: () -> Void

  var body: some View {
    HStack(spacing: 8) {
      Button {
        onEdit()
      } label: {
        Label(language.edit, systemImage: "slider.horizontal.3")
      }
      .help(language.editHelp)

      Button {
        NSWorkspace.shared.activateFileViewerSelecting([asset.url])
      } label: {
        Label(language.finder, systemImage: "finder")
      }
      .help(language.showInFinder)

      Button {
        onExport()
      } label: {
        Label(language.export, systemImage: "square.and.arrow.up")
      }
      .help(language.exportAsset)

      Button {
        onToggleSelection()
      } label: {
        Label(
          isSelected ? language.selected : language.select,
          systemImage: isSelected ? "checkmark.circle.fill" : "circle"
        )
      }
      .help(isSelected ? language.removeFromSelection : language.selectForExport)

      Button {
        onHide()
      } label: {
        Label(language.hideAsset, systemImage: "eye.slash")
      }
      .help(language.hideHelp)
    }
    .buttonStyle(.bordered)
  }
}

private enum AssetClipboard {
  @discardableResult
  static func copyPath(_ url: URL) -> Bool {
    NSPasteboard.general.clearContents()
    return NSPasteboard.general.setString(
      url.standardizedFileURL.path,
      forType: .string
    )
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
