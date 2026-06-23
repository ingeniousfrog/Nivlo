import NivloDomain
import SwiftUI

struct AppSettingsView: View {
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
    }
    .formStyle(.grouped)
    .scrollDisabled(true)
    .padding(16)
    .frame(width: 420, height: 230)
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
}
