import SwiftUI

enum AIConfiguration {
  static let defaultProviderKey = "nivlo.ai.defaultProvider"
}

struct AISettingsView: View {
  @AppStorage(AIConfiguration.defaultProviderKey)
  private var selectedAdapterID = GenerationAdapterRegistry.all.first?.id ?? "openai-images"
  @State private var apiKey = ""
  @State private var statusMessage: String?
  @AppStorage("nivlo.language") private var languageRawValue = NivloLanguage.english.rawValue

  private var language: NivloLanguage {
    NivloLanguage(rawValue: languageRawValue) ?? .english
  }

  var body: some View {
    Form {
      Picker(language.aiProvider, selection: $selectedAdapterID) {
        ForEach(GenerationAdapterRegistry.all, id: \.id) { adapter in
          Text(adapter.displayName).tag(adapter.id)
        }
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
    .formStyle(.grouped)
    .padding(20)
    .frame(width: 420)
    .onAppear {
      apiKey = APIKeyStore.load(providerID: selectedAdapterID) ?? ""
    }
    .onChange(of: selectedAdapterID) { _, newValue in
      apiKey = APIKeyStore.load(providerID: newValue) ?? ""
      statusMessage = nil
    }
  }

  private func saveAPIKey() {
    do {
      try APIKeyStore.save(
        providerID: selectedAdapterID,
        apiKey: apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
      )
      statusMessage = language.apiKeySaved
    } catch {
      statusMessage = error.localizedDescription
    }
  }
}
