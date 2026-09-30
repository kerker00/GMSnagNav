import GMSnagNav
import SwiftUI

/// The library sidebar.
///
/// For now this renders a plain SwiftUI `List(children:)`. It is replaced step by step by
/// `SnagOutline` as the package gains its public API — selection and expansion bindings, drag and
/// drop, context menus and more — so the demo always shows the current feature set.
struct SidebarView: View {
  @Environment(Library.self) private var library
  @Binding var selection: LibraryItem.ID?
  let onError: (Error) -> Void

  var body: some View {
    List(library.roots, children: \.children, selection: $selection) { item in
      Label(item.name, systemImage: item.systemImage)
        .accessibilityIdentifier("sidebar-row-\(item.name)")
        .contextMenu { ItemActions(itemID: item.id, onError: onError) }
    }
    .toolbar {
      ToolbarItem {
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

  /// Adds the item next to the selection: into the selected folder, or the root level otherwise.
  private func add(_ item: LibraryItem) {
    let folder = selection.flatMap { library.item($0)?.isFolder == true ? $0 : nil }
    selection = library.add(item, into: folder)
  }
}
