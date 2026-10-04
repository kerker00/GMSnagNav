import SwiftUI

/// Asks before deleting folders that contain other items, since their contents go with them.
///
/// Whether and how to protect containers is the app's decision; GMSnagNav never deletes anything.
/// The demo asks in every place that deletes: swipe actions, context menu, bottom bar, menu bar
/// and detail view.
struct DeleteConfirmation: ViewModifier {
  @Environment(Library.self) private var library
  /// The items waiting for confirmation; empty while no dialog is shown.
  @Binding var pending: [LibraryItem.ID]
  let delete: ([LibraryItem.ID]) -> Void

  func body(content: Content) -> some View {
    content.confirmationDialog(
      title,
      isPresented: Binding(
        get: { !pending.isEmpty },
        set: { if !$0 { pending = [] } }),
      titleVisibility: .visible
    ) {
      Button("Delete", role: .destructive) { [pending] in
        delete(pending)
      }
    } message: {
      Text(message)
    }
  }

  private var title: String {
    if pending.count == 1, let item = pending.first.flatMap(library.item) {
      return "Delete \"\(item.name)\"?"
    }
    return "Delete \(pending.count) Items?"
  }

  private var message: String {
    // A section's items stay; only folders take their contents with them.
    let contained = pending.filter { library.item($0)?.isSection == false }
      .reduce(0) { $0 + library.descendantCount(of: $1) }
    return contained == 1
      ? "1 item inside will be deleted as well."
      : "\(contained) items inside will be deleted as well."
  }
}

extension View {
  /// Deletes items right away through `delete`, or asks first when `pending` holds folders with
  /// content. Set `pending` with `Library.needsDeleteConfirmation(_:)`.
  func deleteConfirmation(
    pending: Binding<[LibraryItem.ID]>, delete: @escaping ([LibraryItem.ID]) -> Void
  ) -> some View {
    modifier(DeleteConfirmation(pending: pending, delete: delete))
  }
}
