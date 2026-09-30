import SwiftUI

@main
struct SnagNavDemoApp: App {
  @State private var library = Library()

  var body: some Scene {
    WindowGroup {
      ContentView()
        .environment(library)
    }
  }
}
