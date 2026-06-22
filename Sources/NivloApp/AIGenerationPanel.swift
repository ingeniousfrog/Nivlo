import AppKit
import NivloDomain
import SwiftUI
import UniformTypeIdentifiers

struct AIGenerationPanel: View {
  let asset: ImageAsset
  let language: NivloLanguage
  let onGenerated: (GenerationResult) -> Void

  @State private var capability: GenerationCapability = .textToImage
  @State private var prompt = ""
  @State private var negativePrompt = ""
  @State private var strength = 0.75
  @State private var steps = 30
  @State private var statusMessage: String?
  @State private var isGenerating = false

  private var selectedAdapter: (any GenerationAdapter)? {
    GenerationAdapterRegistry.all.first { $0.id == AIConfiguration.providerID }
  }

  private var hasAPIKey: Bool {
    guard let key = APIKeyStore.load(providerID: AIConfiguration.providerID) else { return false }
    return !key.isEmpty
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      if !hasAPIKey {
        ContentUnavailableView {
          Label(language.aiMissingAPIKeyHint, systemImage: "key.slash")
        } description: {
          Text(language.aiConfigureInSettings)
        } actions: {
          Button(language.openSettings) {
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
          }
        }
      } else {
        VStack(alignment: .leading, spacing: 14) {
          Picker(language.aiCapability, selection: $capability) {
            ForEach(GenerationCapability.allCases, id: \.self) { item in
              Text(item.rawValue).tag(item)
            }
          }
          TextField(language.aiPrompt, text: $prompt, axis: .vertical)
            .lineLimit(3...6)
          TextField(language.aiNegativePrompt, text: $negativePrompt, axis: .vertical)
            .lineLimit(2...4)
          Slider(value: $strength, in: 0...1) {
            Text(language.aiStrength)
          }
          Stepper(value: $steps, in: 10...80) {
            Text("\(language.aiSteps): \(steps)")
          }
          Button(language.aiGenerate) {
            generate()
          }
          .buttonStyle(.borderedProminent)
          .disabled(isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
          if let statusMessage {
            Text(statusMessage)
              .font(.caption)
              .foregroundStyle(.secondary)
              .fixedSize(horizontal: false, vertical: true)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }

  private func generate() {
    guard let adapter = selectedAdapter else {
      return
    }
    guard hasAPIKey else {
      statusMessage = language.aiMissingAPIKeyHint
      return
    }
    let panel = NSSavePanel()
    panel.title = language.aiGenerate
    panel.nameFieldStringValue = "\(asset.url.deletingPathExtension().lastPathComponent)-ai.png"
    panel.allowedContentTypes = [.png]
    guard panel.runModal() == .OK, let outputURL = panel.url else {
      return
    }

    isGenerating = true
    statusMessage = language.aiGenerating
    let request = GenerationRequest(
      capability: capability,
      prompt: prompt,
      negativePrompt: negativePrompt,
      sourceImageURL: asset.url,
      strength: strength,
      steps: steps,
      outputURL: outputURL
    )
    Task {
      do {
        let result = try await adapter.generate(request)
        statusMessage = language.aiGenerated
        onGenerated(result)
      } catch {
        statusMessage = error.localizedDescription
      }
      isGenerating = false
    }
  }
}
