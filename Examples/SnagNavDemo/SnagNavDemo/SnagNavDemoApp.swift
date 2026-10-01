import SwiftUI

#if os(macOS)
  import AppKit
#else
  import UIKit
#endif

@main
struct SnagNavDemoApp: App {
  @State private var library = Library()

  /// UI tests start from the sample data, with every setting at its default and a fresh window.
  private let isUITesting = CommandLine.arguments.contains("-ui-testing")

  /// The appearance forced by `-DemoColorScheme light` or `dark`, used for the README screenshots.
  private let colorScheme: ColorScheme? =
    switch UserDefaults.standard.string(forKey: "DemoColorScheme") {
    case "light": .light
    case "dark": .dark
    default: nil
    }

  init() {
    if isUITesting, let domain = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: domain)
    }
    #if os(iOS)
      // An open context menu keeps animating, so UI tests that open one would wait a minute for
      // the app to become idle.
      if CommandLine.arguments.contains("-disable-animations") {
        UIView.setAnimationsEnabled(false)
      }
    #endif
  }

  #if os(macOS)
    private static func resizeWindowForUITests() {
      DispatchQueue.main.async {
        guard let window = NSApplication.shared.windows.first(where: \.isVisible) else { return }
        window.setFrame(NSRect(x: 80, y: 80, width: 960, height: 700), display: true)
      }
    }
  #endif

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(library)
        .preferredColorScheme(colorScheme)
        #if os(macOS)
          .onAppear {
            // A restored, smaller window would clip rows that UI tests interact with.
            if isUITesting { Self.resizeWindowForUITests() }
          }
        #endif
    }
    .commands { DemoCommands() }
    #if os(macOS)
      .defaultSize(width: 960, height: 640)
    #endif
  }
}
