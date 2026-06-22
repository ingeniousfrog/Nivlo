import NivloImaging
import SwiftUI

struct ContentView: View {
  @StateObject private var toolBootstrapper = ToolBootstrapper.shared

  var body: some View {
    LibraryView(toolBootstrapper: toolBootstrapper)
      .task {
        toolBootstrapper.ensureToolsReady()
      }
  }
}
