import NivloDomain
import SwiftUI

struct IndexHealthView: View {
  @ObservedObject var model: LibraryModel
  let language: NivloLanguage

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 20) {
        Text(language.indexHealth)
          .font(.largeTitle.bold())

        LazyVGrid(
          columns: [GridItem(.adaptive(minimum: 180), spacing: 12)],
          spacing: 12
        ) {
          healthCard(
            language.indexedAssets,
            value: "\(model.assets.count)",
            icon: "photo.stack"
          )
          healthCard(
            language.enrichedAssets,
            value: "\(model.enrichments.count)",
            icon: "wand.and.stars"
          )
          healthCard(
            language.failedEnrichments,
            value: "\(model.failedEnrichments.count)",
            icon: "exclamationmark.triangle"
          )
          healthCard(
            language.inaccessibleRoots,
            value: "\(model.inaccessibleRootCount)",
            icon: "externaldrive.badge.exclamationmark"
          )
        }

        GroupBox(language.lastSuccessfulWork) {
          VStack(alignment: .leading, spacing: 10) {
            healthRow(
              language.lastScan,
              date: model.indexHealth.lastSuccessfulScanAt
            )
            healthRow(
              language.lastEnrichment,
              date: model.indexHealth.lastSuccessfulEnrichmentAt
            )
            if let message = model.indexHealth.lastErrorMessage {
              LabeledContent(language.lastIndexError, value: message)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }

        if !model.failedEnrichments.isEmpty {
          GroupBox(language.failedEnrichments) {
            VStack(alignment: .leading, spacing: 8) {
              ForEach(model.failedEnrichments, id: \.assetID) { failure in
                VStack(alignment: .leading, spacing: 2) {
                  Text(failure.assetID.fileIdentifier)
                    .font(.caption.monospaced())
                  Text(failure.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
          }
        }

        GroupBox(language.indexActions) {
          VStack(alignment: .leading, spacing: 12) {
            HStack {
              Button(language.pause) {
                Task { await model.pauseEnrichment() }
              }
              .disabled(!model.isEnriching)
              Button(language.resume) {
                Task { await model.resumeEnrichment() }
              }
              .disabled(!model.isEnriching)
              Button(language.cancel) {
                Task { await model.cancelEnrichment() }
              }
              .disabled(!model.isEnriching)
            }
            HStack {
              Button(language.retryFailures) {
                Task { await model.retryFailedEnrichments() }
              }
              .disabled(model.failedEnrichments.isEmpty)
              Button(language.rescanAll) {
                Task { await model.rescanAllRoots() }
              }
              .disabled(model.isScanning)
            }
            HStack {
              Button(language.rebuildSearch) {
                Task { await model.rebuildSearchIndex() }
              }
              Button(language.verifyIntegrity) {
                Task { await model.verifyIndexIntegrity() }
              }
              Button(language.rebuildRichIndex, role: .destructive) {
                Task { await model.rebuildRichIndex() }
              }
              .disabled(model.isEnriching)
            }
          }
          .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(28)
    }
    .navigationTitle(language.indexHealth)
  }

  private func healthCard(
    _ title: String,
    value: String,
    icon: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(title, systemImage: icon)
        .font(.caption)
        .foregroundStyle(.secondary)
      Text(value)
        .font(.title.bold().monospacedDigit())
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .padding(16)
    .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 12))
  }

  private func healthRow(_ title: String, date: Date?) -> some View {
    LabeledContent(
      title,
      value: date?.formatted(date: .abbreviated, time: .standard)
        ?? language.never
    )
  }
}
