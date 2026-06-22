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
  @State private var selectedAdapterID = GenerationAdapterRegistry.all.first?.id ?? "openai-images"
  @State private var apiKey = ""
  @State private var statusMessage: String?
  @State private var isGenerating = false

  private var selectedAdapter: (any GenerationAdapter)? {
    GenerationAdapterRegistry.all.first { $0.id == selectedAdapterID }
  }

  var body: some View {
    Form {
      Picker(language.aiProvider, selection: $selectedAdapterID) {
        ForEach(GenerationAdapterRegistry.all, id: \.id) { adapter in
          Text(adapter.displayName).tag(adapter.id)
        }
      }
      SecureField(language.aiAPIKey, text: $apiKey)
        .onAppear {
          apiKey = APIKeyStore.load(providerID: selectedAdapterID) ?? ""
        }
        .onChange(of: selectedAdapterID) { _, newValue in
          apiKey = APIKeyStore.load(providerID: newValue) ?? ""
        }
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
      HStack {
        Button(language.saveAPIKey) {
          try? APIKeyStore.save(providerID: selectedAdapterID, apiKey: apiKey)
          statusMessage = language.apiKeySaved
        }
        Button(language.aiGenerate) {
          generate()
        }
        .buttonStyle(.borderedProminent)
        .disabled(isGenerating || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
      }
      if let statusMessage {
        Text(statusMessage)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .frame(minWidth: 360)
  }

  private func generate() {
    guard let adapter = selectedAdapter else {
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
        try? APIKeyStore.save(providerID: selectedAdapterID, apiKey: apiKey)
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
