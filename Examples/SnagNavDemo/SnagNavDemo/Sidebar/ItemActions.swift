import SwiftUI

/// Menu actions for one item, shared by the sidebar context menu and the detail view.
///
/// "Move to" is the keyboard- and menu-friendly fallback for drag and drop, which every outline
/// should offer for accessibility.
struct ItemActions: View {
  @Environment(Library.self) private var library
  let itemID: LibraryItem.ID
  let onError: (Error) -> Void

  var body: some View {
    Menu("Move to", systemImage: "folder") {
      Button("Top Level") { move(into: nil) }
        .disabled(!library.canMove(itemID, into: nil))
      Divider()
      ForEach(library.allFolders, id: \.item.id) { folder in
        Button(indentedName(folder.item.name, depth: folder.depth)) {
          move(into: folder.item.id)
        }
        .disabled(!library.canMove(itemID, into: folder.item.id))
      }
    }
    Divider()
    Button("Delete", systemImage: "trash", role: .destructive) {
      library.delete(itemID)
    }
  }

  private func move(into folder: LibraryItem.ID?) {
    do {
      try library.move(itemID, into: folder)
    } catch {
      onError(error)
    }
  }

  private func indentedName(_ name: String, depth: Int) -> String {
    String(repeating: "    ", count: depth) + name
  }
}
