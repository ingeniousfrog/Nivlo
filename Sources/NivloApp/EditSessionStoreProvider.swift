import Foundation
import NivloPersistence

enum EditSessionStoreProvider {
  static let shared: FileEditSessionStore? = {
    guard
      let applicationSupportURL = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
      ).first
    else {
      return nil
    }
    return FileEditSessionStore(
      baseDirectory:
        applicationSupportURL
        .appending(path: "Nivlo", directoryHint: .isDirectory)
        .appending(path: "EditSessions", directoryHint: .isDirectory)
    )
  }()
}
