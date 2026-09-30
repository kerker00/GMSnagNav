import SwiftUI

struct ContentView: View {
  @Environment(Library.self) private var library
  @State private var selection: LibraryItem.ID?
  @State private var errorMessage: String?

  var body: some View {
    NavigationSplitView {
      SidebarView(selection: $selection, onError: show)
        .navigationTitle("Library")
        #if os(macOS)
          .navigationSplitViewColumnWidth(min: 220, ideal: 260)
        #endif
    } detail: {
      if let selection, library.item(selection) != nil {
        ItemDetailView(itemID: selection, onError: show)
      } else {
        ContentUnavailableView(
          "No Selection", systemImage: "sidebar.left",
          description: Text("Select an item in the sidebar."))
      }
    }
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

  private func show(_ error: Error) {
    errorMessage = error.localizedDescription
  }
}

#Preview {
  ContentView()
    .environment(Library())
}
