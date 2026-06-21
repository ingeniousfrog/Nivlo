import SwiftUI

@main
struct NivloApp: App {
  var body: some Scene {
    WindowGroup {
      LibraryView()
        .frame(minWidth: 900, minHeight: 620)
    }
    .windowStyle(.hiddenTitleBar)
  }
}
