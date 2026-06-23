import AppKit
import SwiftUI

@main
struct NivloApp: App {
  @NSApplicationDelegateAdaptor(NivloAppDelegate.self)
  private var appDelegate

  private var isUISmoke: Bool {
    CommandLine.arguments.contains("--ui-smoke")
  }

  var body: some Scene {
    WindowGroup("Nivlo") {
      Group {
        if isUISmoke {
          EditorSmokeView()
        } else {
          ContentView()
        }
      }
      .frame(minWidth: 900, minHeight: 620)
    }
    .defaultSize(
      width: isUISmoke ? 1_400 : 1_100,
      height: isUISmoke ? 900 : 720
    )

    Settings {
      AppSettingsView()
        .nivloAppAppearance()
    }
    .windowResizability(.contentSize)
  }
}

private final class NivloAppDelegate: NSObject, NSApplicationDelegate {
  private var fallbackWindow: NSWindow?

  func applicationDidFinishLaunching(_ notification: Notification) {
    AppAppearance.applyStoredAppearance()
    NSApp.setActivationPolicy(.regular)
    DispatchQueue.main.async { [weak self] in
      self?.ensureVisibleMainWindow()
      NSApp.activate(ignoringOtherApps: true)
    }
  }

  @MainActor
  private func ensureVisibleMainWindow() {
    if let window = NSApp.windows.first(where: { $0.isVisible }) {
      if CommandLine.arguments.contains("--ui-smoke") {
        window.setContentSize(NSSize(width: 1_400, height: 900))
        window.center()
      }
      return
    }

    let isUISmoke = CommandLine.arguments.contains("--ui-smoke")
    let window = NSWindow(
      contentRect: NSRect(
        x: 0,
        y: 0,
        width: isUISmoke ? 1_400 : 1_100,
        height: isUISmoke ? 900 : 720
      ),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.title = "Nivlo"
    window.center()
    window.contentViewController = NSHostingController(rootView: ContentView())
    window.makeKeyAndOrderFront(nil)
    fallbackWindow = window
  }
}
