import SwiftUI

#if os(macOS)
  import AppKit
#endif

@main
struct SnagNavDemoApp: App {
  @State private var library = Library()

  /// UI tests start from the sample data, with every setting at its default and a fresh window.
  private let isUITesting = CommandLine.arguments.contains("-ui-testing")

  init() {
    if isUITesting, let domain = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: domain)
    }
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
        #if os(macOS)
          .onAppear {
            // A restored, smaller window would clip rows that UI tests interact with.
            if isUITesting { Self.resizeWindowForUITests() }
          }
        #endif
    }
    #if os(macOS)
      .defaultSize(width: 960, height: 640)
    #endif
  }
}
