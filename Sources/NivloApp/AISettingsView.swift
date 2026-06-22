import NivloDomain
import SwiftUI

enum AIConfiguration {
  static let defaultProviderKey = "nivlo.ai.defaultProvider"
  static let providerID = "openai-images"
  static let apiKeyURL = URL(string: "https://synclip.ai/dev")!
}

struct AISettingsView: View {
  @State private var apiKey = ""
  @State private var statusMessage: String?
  @AppStorage("nivlo.library.refreshInterval")
  private var refreshIntervalRawValue = LibraryRefreshInterval.fifteenMinutes.rawValue
  @AppStorage("nivlo.language") private var languageRawValue = NivloLanguage.english.rawValue
  @AppStorage(AppAppearance.storageKey) private var appearanceRawValue = AppAppearance.light.rawValue

  private var language: NivloLanguage {
    NivloLanguage(rawValue: languageRawValue) ?? .english
  }

  var body: some View {
    Form {
      Section(language.library) {
        Picker(language.appearance, selection: $appearanceRawValue) {
          Text(language.appearanceLight).tag(AppAppearance.light.rawValue)
          Text(language.appearanceDark).tag(AppAppearance.dark.rawValue)
          Text(language.appearanceSystem).tag(AppAppearance.system.rawValue)
        }
        Picker(language.autoRefresh, selection: $refreshIntervalRawValue) {
          ForEach(LibraryRefreshInterval.allCases) { interval in
            Text(refreshIntervalTitle(interval)).tag(interval.rawValue)
          }
        }
        Text(language.refreshLibrary)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(language.aiSettingsTitle) {
        LabeledContent {
          Link(language.aiGetAPIKeyLink, destination: AIConfiguration.apiKeyURL)
        } label: {
          Text(language.aiGetAPIKeyHint)
        }
        SecureField(language.aiAPIKey, text: $apiKey)
        HStack {
          Button(language.saveAPIKey) {
            saveAPIKey()
          }
          .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          if let statusMessage {
            Text(statusMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }
        Text(language.aiConfigureInSettings)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding(20)
    .frame(width: 460)
    .onAppear {
      apiKey = APIKeyStore.load(providerID: AIConfiguration.providerID) ?? ""
    }
  }

  private func refreshIntervalTitle(_ interval: LibraryRefreshInterval) -> String {
    switch interval {
    case .off:
      language.refreshOff
    case .fiveMinutes:
      language.refreshEveryFiveMinutes
    case .fifteenMinutes:
      language.refreshEveryFifteenMinutes
    case .thirtyMinutes:
      language.refreshEveryThirtyMinutes
    case .hourly:
      language.refreshHourly
    }
  }

  private func saveAPIKey() {
    do {
      try APIKeyStore.save(
        providerID: AIConfiguration.providerID,
        apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      statusMessage = language.apiKeySaved
    } catch {
      statusMessage = error.localizedDescription
    }
  }
}
