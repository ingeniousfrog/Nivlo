import SwiftUI

struct ContentView: View {
  var body: some View {
    LibraryView()
      .overlay(alignment: .bottomTrailing) {
        VStack(alignment: .trailing, spacing: 2) {
          Text("Nivlo")
            .font(.caption.weight(.semibold))
          Text("Local visual asset workspace")
            .font(.caption2)
        }
        .foregroundStyle(.secondary)
        .padding(10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        .padding(12)
        .accessibilityElement(children: .combine)
      }
  }
}
