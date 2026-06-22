import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
  case light
  case dark
  case system

  var id: String { rawValue }

  static let storageKey = "nivlo.appearance"

  var preferredColorScheme: ColorScheme? {
    switch self {
    case .light:
      .light
    case .dark:
      .dark
    case .system:
      nil
    }
  }

  @MainActor
  func applyToAppKit() {
    switch self {
    case .light:
      NSApp.appearance = NSAppearance(named: .aqua)
    case .dark:
      NSApp.appearance = NSAppearance(named: .darkAqua)
    case .system:
      NSApp.appearance = nil
    }
  }

  static func current() -> AppAppearance {
    let rawValue = UserDefaults.standard.string(forKey: storageKey) ?? AppAppearance.light.rawValue
    return AppAppearance(rawValue: rawValue) ?? .light
  }

  @MainActor
  static func applyStoredAppearance() {
    current().applyToAppKit()
  }
}

struct AppAppearanceModifier: ViewModifier {
  @AppStorage(AppAppearance.storageKey) private var rawValue = AppAppearance.light.rawValue

  private var appearance: AppAppearance {
    AppAppearance(rawValue: rawValue) ?? .light
  }

  func body(content: Content) -> some View {
    content
      .preferredColorScheme(appearance.preferredColorScheme)
      .onAppear {
        appearance.applyToAppKit()
      }
      .onChange(of: rawValue) { _, _ in
        appearance.applyToAppKit()
      }
  }
}

extension View {
  func nivloAppAppearance() -> some View {
    modifier(AppAppearanceModifier())
  }
}
