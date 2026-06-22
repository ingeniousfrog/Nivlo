import NivloImaging
import SwiftUI

struct ContentView: View {
  @StateObject private var toolBootstrapper = ToolBootstrapper.shared
  @AppStorage("nivlo.language") private var languageRawValue =
    NivloLanguage.english.rawValue

  private var language: NivloLanguage {
    NivloLanguage(rawValue: languageRawValue) ?? .english
  }

  var body: some View {
    LibraryView()
      .overlay(alignment: .bottomTrailing) {
        VStack(alignment: .trailing, spacing: 8) {
          ToolHealthView(bootstrapper: toolBootstrapper, language: language)
          VStack(alignment: .trailing, spacing: 2) {
            Text("Nivlo")
              .font(.caption.weight(.semibold))
            Text("Local visual asset workspace")
              .font(.caption2)
          }
          .foregroundStyle(.secondary)
          .padding(10)
          .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        .padding(12)
      }
      .task {
        toolBootstrapper.ensureToolsReady()
      }
  }
}
