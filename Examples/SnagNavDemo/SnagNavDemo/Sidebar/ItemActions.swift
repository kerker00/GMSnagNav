import SwiftUI

/// Actions for one item in the detail view.
///
/// "Move to" is the keyboard- and menu-friendly fallback for drag and drop, which every outline
/// should offer for accessibility.
struct ItemActions: View {
  @Environment(Library.self) private var library
  let itemID: LibraryItem.ID
  let onError: (Error) -> Void
  @State private var pendingDeletion: [LibraryItem.ID] = []

  var body: some View {
    Menu {
      Button("Top Level") { move(into: nil) }
        .disabled(!library.canMove(itemID, into: nil))
      Divider()
      ForEach(library.allFolders, id: \.item.id) { folder in
        Button(indentedName(folder.item.name, depth: folder.depth)) {
          move(into: folder.item.id)
        }
        .disabled(!library.canMove(itemID, into: folder.item.id))
      }
    } label: {
      Label("Move to", systemImage: "folder")
    }
    Button(role: .destructive) {
      if library.needsDeleteConfirmation([itemID]) {
        pendingDeletion = [itemID]
      } else {
        library.delete(itemID)
      }
    } label: {
      Label("Delete", systemImage: "trash")
        .frame(maxWidth: Self.fillsWidth, alignment: .leading)
    }
    .deleteConfirmation(pending: $pendingDeletion) { ids in ids.forEach(library.delete) }
  }

  /// On macOS, the button fills the width its container gives it, so it can match the menu.
  private static var fillsWidth: CGFloat? {
    #if os(macOS)
      .infinity
    #else
      nil
    #endif
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
