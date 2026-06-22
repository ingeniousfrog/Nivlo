import AppKit
import SwiftUI

@main
struct NivloApp: App {
  @NSApplicationDelegateAdaptor(NivloAppDelegate.self)
  private var appDelegate

  var body: some Scene {
    WindowGroup("Nivlo") {
      ContentView()
        .frame(minWidth: 900, minHeight: 620)
    }
    .defaultSize(width: 1100, height: 720)

    Settings {
      AISettingsView()
        .nivloAppAppearance()
    }
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
    if NSApp.windows.contains(where: { $0.isVisible }) {
      return
    }

    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 1100, height: 720),
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
