import GMSnagNav
import SwiftUI

struct ContentView: View {
  @Environment(Library.self) private var library
  @State private var selection: LibraryItem.ID?
  @State private var errorMessage: String?
  /// Which column a collapsed split view shows, such as on iPhone.
  @State private var compactColumn = NavigationSplitViewColumn.sidebar
  @State private var columnVisibility = NavigationSplitViewVisibility.all
  @State private var navigationRequest: OutlineNavigationRequest<LibraryItem.ID>?
  @State private var expansion: Set<LibraryItem.ID> = []
  @State private var searchText = ""
  @State private var renamingID: LibraryItem.ID?
  @State private var menuActive = false
  @State private var menuGeneration = UUID()

  var body: some View {
    Group {
      if CommandLine.arguments.contains("-ui-testing"),
        CommandLine.arguments.contains("-sidebar-only")
      {
        // Audit the real sidebar independently of the demo's navigation and detail views.
        sidebar
          .frame(width: 320)
      } else {
        splitView
      }
    }
    .onAppear {
      menuActive = true
      menuGeneration = UUID()
    }
    .onDisappear { menuActive = false }
    .onChange(of: ObjectIdentifier(library)) { menuGeneration = UUID() }
  }

  private var outlineActions: OutlineActions<LibraryItem> {
    OutlineActions(
      data: { library.roots }, children: \.children,
      isPinned: { library.isPinned($0.id) },
      validate: library.dropResult(for:), perform: performModelChange)
  }

  private var menuAvailability: () -> Bool {
    let generation = menuGeneration
    return {
      menuActive && menuGeneration == generation && renamingID == nil
        && searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private var sidebar: some View {
    SidebarView(
      selection: $selection, navigationRequest: $navigationRequest, expansion: $expansion,
      searchText: $searchText, renamingID: $renamingID, outlineActions: outlineActions,
      menuAvailability: menuAvailability, onActionResult: handleAction, onError: show)
  }

  private var splitView: some View {
    NavigationSplitView(columnVisibility: $columnVisibility, preferredCompactColumn: $compactColumn)
    {
      sidebar
        .navigationTitle("Library")
        #if os(macOS)
          .navigationSplitViewColumnWidth(min: 225, ideal: 260, max: 400)
        #endif
    } detail: {
      if let selection, library.item(selection) != nil {
        // A fresh detail view per item, so its state starts from the selected item.
        ItemDetailView(
          itemID: selection, outlineActions: outlineActions, expanded: { expansion },
          menuAvailability: menuAvailability, onActionResult: handleAction, onError: show
        ) {
          navigationRequest = .reveal(selection, focus: true)
          columnVisibility = .all
          compactColumn = .sidebar
        }
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
    // Deleting the selected item, or a folder around it, ends the selection, so Delete and the
    // bottom bar don't act on an item that is gone.
    .onChange(of: library.roots) {
      if let selection, library.item(selection) == nil { self.selection = nil }
    }
    .alert(
      "Action Failed",
      isPresented: Binding(
        get: { errorMessage != nil },
        set: { if !$0 { errorMessage = nil } })
    ) {
      // Not a cancel button: Return dismisses only the alert's default button.
      Button("OK") {}
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

  private func performModelChange(
    _ proposal: OutlineDropProposal<LibraryItem.ID>, _ operation: OutlineDropOperation
  ) -> Bool {
    do {
      try library.performDrop(proposal, operation: operation)
      if let parent = proposal.target.parent { expansion.insert(parent) }
      return true
    } catch {
      show(error)
      return false
    }
  }

  private func handleAction(_ result: OutlineActionResult<LibraryItem.ID>) {
    switch result {
    case .completed(let proposal, .move):
      guard let selection else { return }
      var current: LibraryItem.ID? = selection
      while let id = current {
        if proposal.draggedIDs.contains(id) {
          navigationRequest = .reveal(selection)
          return
        }
        current = library.parent(of: id)
      }
    case .completed, .failed: break
    case .sourceUnavailable: errorMessage = "The selected items changed. Open the menu again."
    case .targetUnavailable: errorMessage = "The destination no longer exists. Open the menu again."
    case .unavailable: errorMessage = "This action is no longer available."
    case .rejected: errorMessage = "These items cannot be transferred to that destination."
    }
  }
}

#Preview {
  ContentView()
    .environment(Library())
}
