import GMSnagNav
import SwiftUI

struct ContentView: View {
  @Environment(Library.self) private var library
  @State private var selection: LibraryItem.ID?
  @State private var errorMessage: String?
  /// Which column a collapsed split view shows, such as on iPhone.
  @State private var compactColumn = NavigationSplitViewColumn.sidebar

  var body: some View {
    if CommandLine.arguments.contains("-ui-testing"),
      CommandLine.arguments.contains("-sidebar-only")
    {
      // Audit the real sidebar independently of the demo's navigation and detail views.
      SidebarView(selection: $selection, onError: show)
        .frame(width: 320)
    } else {
      splitView
    }
  }

  private var splitView: some View {
    NavigationSplitView(preferredCompactColumn: $compactColumn) {
      SidebarView(selection: $selection, onError: show)
        .navigationTitle("Library")
        #if os(macOS)
          .navigationSplitViewColumnWidth(min: 225, ideal: 260, max: 400)
        #endif
    } detail: {
      if let selection, library.item(selection) != nil {
        // A fresh detail view per item, so its state starts from the selected item.
        ItemDetailView(itemID: selection, onError: show)
          .id(selection)
      } else {
        ContentUnavailableView(
          "No Selection", systemImage: "sidebar.left",
          description: Text("Select an item in the sidebar.")
        )
        // The window shows the current section, never the app's name.
        .navigationTitle("Library")
        #if os(macOS)
          .navigationSubtitle(itemCountText(library.itemCount))
        #endif
      }
    }
    // On iPhone: open the detail for a selection, clear the selection on the way back.
    .outlineCompactNavigation(selection: $selection, column: $compactColumn)
    .alert(
      "Action Failed",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } })
    ) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(errorMessage ?? "")
    }
  }

  private func itemCountText(_ count: Int) -> String {
    count == 1 ? "1 item" : "\(count) items"
  }

  private func show(_ error: Error) {
    errorMessage = error.localizedDescription
  }
}

#Preview {
  ContentView()
    .environment(Library())
}
