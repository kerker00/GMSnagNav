import GMSnagNav
import SwiftUI

/// The library sidebar, built with `SnagOutline`.
///
/// Selection and expansion are plain bindings owned by the app: the toolbar's expand and collapse
/// buttons and the "reveal new item" behavior simply change the `expansion` set.
struct SidebarView: View {
  @Environment(Library.self) private var library
  @Binding var selection: LibraryItem.ID?
  let onError: (Error) -> Void

  @State private var expansion: Set<LibraryItem.ID> = []

  var body: some View {
    SnagOutline(
      library.roots, children: \.children, selection: $selection, expansion: $expansion
    ) { item in
      Label(item.name, systemImage: item.systemImage)
        .accessibilityIdentifier("sidebar-row-\(item.name)")
        .contextMenu { ItemActions(itemID: item.id, onError: onError) }
    }
    .onAppear {
      // Start with the top-level folders open.
      expansion = Set(library.roots.filter(\.isFolder).map(\.id))
    }
    .toolbar {
      ToolbarItemGroup {
        Menu {
          Button("Expand All", systemImage: "arrow.down.right.and.arrow.up.left") {
            expansion = Set(library.allFolders.map(\.item.id))
          }
          Button("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right") {
            expansion = []
          }
        } label: {
          Label("Outline", systemImage: "list.bullet.indent")
        }

        Menu {
          Button("New Folder", systemImage: "folder.badge.plus") { add(.folder("New Folder")) }
          Button("New Document", systemImage: "doc.badge.plus") { add(.document("New Document")) }
        } label: {
          Label("Add", systemImage: "plus")
        }
      }
    }
    .safeAreaInset(edge: .bottom) {
      Text("GMSnagNav \(GMSnagNav.version)")
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(8)
    }
  }

  /// Adds the item next to the selection — into the selected folder, or the root level otherwise —
  /// and opens that folder so the new item is visible.
  private func add(_ item: LibraryItem) {
    let folder = selection.flatMap { library.item($0)?.isFolder == true ? $0 : nil }
    if let folder {
      expansion.insert(folder)
    }
    selection = library.add(item, into: folder)
  }
}
