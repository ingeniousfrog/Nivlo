import NivloDomain
import NivloImaging
import SwiftUI

struct AssetInspectorPanel: View {
  let asset: ImageAsset
  let enrichment: AssetEnrichment?
  let language: NivloLanguage

  @State private var histogram: ImageHistogram?
  @State private var videoProbe: VideoProbeInfo?
  @State private var didFinishVideoLoad = false
  @State private var copyFeedback: CopyFeedback?
  @State private var copyFeedbackTask: Task<Void, Never>?

  private var details: AssetPreviewDetails {
    AssetPreviewDetails(
      asset: asset,
      enrichment: enrichment,
      videoProbe: videoProbe
    )
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if asset.mediaKind == .image {
        histogramSection
      }

      fileSection

      if asset.mediaKind == .image {
        imageSection
      }

      if asset.mediaKind == .video {
        videoSection
      }

      if hasCaptureDetails {
        captureSection
      }

      if hasIndexDetails {
        indexSection
      }

      locationSection
    }
    .task(id: asset.url) {
      histogram = nil
      videoProbe = nil
      didFinishVideoLoad = false

      switch asset.mediaKind {
      case .image:
        histogram = try? await Task.detached(priority: .utility) {
          try ImageHistogramAnalyzer().analyze(url: asset.url)
        }.value
      case .video:
        videoProbe = await VideoMetadataLoader().load(url: asset.url)
        didFinishVideoLoad = true
      case .unsupported:
        break
      }
    }
    .onDisappear {
      copyFeedbackTask?.cancel()
    }
  }

  private var histogramSection: some View {
    InspectorSection(title: language.histogram) {
      if let histogram {
        ImageHistogramView(
          histogram: histogram,
          shadowClippingLabel: language.shadowClipping,
          highlightClippingLabel: language.highlightClipping
        )
      } else {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity, minHeight: 88, alignment: .center)
      }
    }
  }

  private var fileSection: some View {
    InspectorSection(title: language.inspectorFileSection) {
      InspectorField(label: language.format, value: details.format)
      InspectorField(label: language.mediaType, value: mediaTypeTitle)
      InspectorField(
        label: language.size,
        value: details.fileSize,
        monospacedValue: true
      )

      if details.createdAt != nil || details.modifiedAt != nil {
        InspectorDivider()
        dateFields
      }
    }
  }

  @ViewBuilder
  private var dateFields: some View {
    switch (details.createdAt, details.modifiedAt) {
    case let (created?, modified?)
    where abs(created.timeIntervalSince(modified)) < 60:
      InspectorField(
        label: language.created,
        value: formattedDate(created)
      )
    case let (created?, modified?):
      InspectorFieldPair(
        leading: InspectorFieldModel(
          label: language.created,
          value: formattedDate(created)
        ),
        trailing: InspectorFieldModel(
          label: language.modified,
          value: formattedDate(modified)
        )
      )
    case let (created?, nil):
      InspectorField(label: language.created, value: formattedDate(created))
    case let (nil, modified?):
      InspectorField(label: language.modified, value: formattedDate(modified))
    default:
      EmptyView()
    }
  }

  @ViewBuilder
  private var imageSection: some View {
    if details.dimensions != nil
      || details.megapixels != nil
      || details.aspectRatio != nil
    {
      InspectorSection(title: language.inspectorImageSection) {
        if let dimensions = details.dimensions,
          let megapixels = details.megapixels
        {
          InspectorFieldPair(
            leading: InspectorFieldModel(
              label: language.dimensions,
              value: dimensions,
              monospaced: true
            ),
            trailing: InspectorFieldModel(
              label: language.megapixels,
              value: megapixels,
              monospaced: true
            )
          )
        } else if let dimensions = details.dimensions {
          InspectorField(
            label: language.dimensions,
            value: dimensions,
            monospacedValue: true
          )
        } else if let megapixels = details.megapixels {
          InspectorField(
            label: language.megapixels,
            value: megapixels,
            monospacedValue: true
          )
        }

        if let aspectRatio = details.aspectRatio {
          InspectorField(
            label: language.aspectRatio,
            value: aspectRatio,
            monospacedValue: true
          )
        }
      }
    }
  }

  @ViewBuilder
  private var videoSection: some View {
    InspectorSection(title: language.inspectorVideoSection) {
      if !didFinishVideoLoad {
        ProgressView()
          .controlSize(.small)
          .frame(maxWidth: .infinity, alignment: .leading)
          .padding(.vertical, 8)
      } else if hasVideoDetails {
        if let duration = details.duration {
          videoDurationHero(duration)
          InspectorDivider()
        }

        InspectorFieldPair(
          leading: InspectorFieldModel(
            label: language.frameRate,
            value: details.frameRate ?? "—",
            monospaced: true
          ),
          trailing: InspectorFieldModel(
            label: language.audioTrack,
            value: audioTrackTitle
          )
        )

        if details.dimensions != nil || details.aspectRatio != nil {
          InspectorFieldPair(
            leading: InspectorFieldModel(
              label: language.dimensions,
              value: details.dimensions ?? "—",
              monospaced: true
            ),
            trailing: InspectorFieldModel(
              label: language.aspectRatio,
              value: details.aspectRatio ?? "—",
              monospaced: true
            )
          )
        }

        if details.videoCodec != nil || details.audioCodec != nil {
          InspectorDivider()
          InspectorFieldPair(
            leading: InspectorFieldModel(
              label: language.videoCodec,
              value: formattedCodec(details.videoCodec)
            ),
            trailing: InspectorFieldModel(
              label: language.audioCodec,
              value: formattedCodec(details.audioCodec)
            )
          )
        }
      } else {
        Text(language.videoMetadataUnavailable)
          .font(.caption)
          .foregroundStyle(.secondary)
          .padding(.vertical, 4)
      }
    }
  }

  private var captureSection: some View {
    InspectorSection(title: language.inspectorCameraSection) {
      if let capturedAt = details.capturedAt {
        InspectorField(
          label: language.captured,
          value: formattedDate(capturedAt)
        )
      }

      if details.camera != nil || details.lens != nil {
        if details.capturedAt != nil {
          InspectorDivider()
        }
        InspectorFieldPair(
          leading: InspectorFieldModel(
            label: language.camera,
            value: details.camera ?? "—"
          ),
          trailing: details.lens.map {
            InspectorFieldModel(label: language.lens, value: $0)
          }
        )
      }

      if let exposure = details.exposure {
        if details.capturedAt != nil || details.camera != nil || details.lens != nil {
          InspectorDivider()
        }
        InspectorField(
          label: language.exposure,
          value: exposure,
          monospacedValue: true
        )
      }
    }
  }

  @ViewBuilder
  private var indexSection: some View {
    InspectorSection(title: language.inspectorMetadataSection) {
      if !details.dominantColors.isEmpty {
        InspectorColorPalette(
          label: language.dominantColors,
          colors: details.dominantColors
        )
      }
      if !details.dominantColors.isEmpty && !details.keywords.isEmpty {
        InspectorDivider()
      }
      if !details.keywords.isEmpty {
        InspectorTagRow(label: language.keywords, tags: details.keywords)
      }
    }
  }

  private var locationSection: some View {
    InspectorSection(title: language.path) {
      HStack(alignment: .top, spacing: 8) {
        Text(details.path)
          .font(.caption.monospaced())
          .foregroundStyle(.secondary)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
          .fixedSize(horizontal: false, vertical: true)

        Button {
          copyPath()
        } label: {
          if let copyFeedback {
            Image(
              systemName: copyFeedback == .success
                ? "checkmark.circle.fill"
                : "exclamationmark.triangle.fill"
            )
            .foregroundStyle(copyFeedback == .success ? Color.green : Color.orange)
          } else {
            Image(systemName: "doc.on.doc")
          }
        }
        .buttonStyle(.borderless)
        .help(language.copyPath)
      }
      .padding(.vertical, 2)
    }
  }

  private func videoDurationHero(_ duration: String) -> some View {
    HStack(alignment: .firstTextBaseline, spacing: 10) {
      Text(language.duration)
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(width: InspectorMetrics.labelWidth, alignment: .leading)

      Text(duration)
        .font(.system(.title3, design: .monospaced).weight(.semibold))
        .foregroundStyle(.primary)
        .textSelection(.enabled)
    }
    .padding(.vertical, 2)
  }

  private var mediaTypeTitle: String {
    switch details.mediaKind {
    case .image:
      language.mediaTypeImage
    case .video:
      language.mediaTypeVideo
    case .unsupported:
      language.mediaTypeUnsupported
    }
  }

  private var audioTrackTitle: String {
    guard let hasAudio = details.hasAudio else { return "—" }
    return hasAudio ? language.audioPresent : language.audioAbsent
  }

  private var hasVideoDetails: Bool {
    details.duration != nil
      || details.dimensions != nil
      || details.frameRate != nil
      || details.hasAudio != nil
      || details.videoCodec != nil
  }

  private var hasCaptureDetails: Bool {
    details.capturedAt != nil
      || details.camera != nil
      || details.lens != nil
      || details.exposure != nil
  }

  private var hasIndexDetails: Bool {
    !details.dominantColors.isEmpty || !details.keywords.isEmpty
  }

  private func formattedCodec(_ codec: String?) -> String {
    guard let codec else { return "—" }
    return codec.uppercased()
  }

  private func formattedDate(_ date: Date) -> String {
    date.formatted(date: .abbreviated, time: .shortened)
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
