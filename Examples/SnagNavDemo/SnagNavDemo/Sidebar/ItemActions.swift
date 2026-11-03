import GMSnagNav
import SwiftUI

/// Actions for one item in the detail view.
///
/// "Move to" is the keyboard- and menu-friendly fallback for drag and drop, which every outline
/// should offer for accessibility.
struct ItemActions: View {
  @Environment(Library.self) private var library
  let itemID: LibraryItem.ID
  let outlineActions: OutlineActions<LibraryItem>
  let expanded: () -> Set<LibraryItem.ID>
  let isAvailable: () -> Bool
  let onActionResult: (OutlineActionResult<LibraryItem.ID>) -> Void
  let onError: (Error) -> Void
  @Environment(\.locale) private var locale
  @State private var pendingDeletion: [LibraryItem.ID] = []

  var body: some View {
    let moves = destinations(.move)
    let copies = destinations(.copy)
    Menu {
      OutlineMenuItems(moves)
    } label: {
      Label("Move to", systemImage: "folder")
    }
    .accessibilityIdentifier("detail-move-menu")
    Menu {
      OutlineMenuItems(copies)
    } label: {
      Label("Copy to", systemImage: "doc.on.doc")
    }
    .accessibilityIdentifier("detail-copy-menu")
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

  private func destinations(_ operation: OutlineDropOperation) -> [OutlineMenuItem] {
    outlineActions.destinationItems(
      for: [itemID], operation: operation, expanded: expanded, isAvailable: isAvailable,
      locale: locale, onCompletion: onActionResult
    ) { $0.name }
  }
}
