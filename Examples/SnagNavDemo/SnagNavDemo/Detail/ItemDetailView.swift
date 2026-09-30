import SwiftUI

struct ItemDetailView: View {
  @Environment(Library.self) private var library
  let itemID: LibraryItem.ID
  let onError: (Error) -> Void

  @State private var name = ""

  var body: some View {
    if let item = library.item(itemID) {
      Form {
        Section {
          #if os(macOS)
            nameField
          #else
            // iOS forms show a text field's title only as a placeholder, so label it explicitly.
            LabeledContent("Name") {
              nameField.multilineTextAlignment(.trailing)
            }
          #endif
          LabeledContent("Kind", value: item.isFolder ? "Folder" : "Document")
          LabeledContent("Location") {
            Text(library.path(to: itemID).joined(separator: " › "))
              .accessibilityIdentifier("detail-location")
          }
          if let children = item.children {
            LabeledContent("Items", value: "\(children.count)")
          }
        }
        Section {
          ItemActions(itemID: itemID, onError: onError)
        }
      }
      .formStyle(.grouped)
      .navigationTitle(item.name)
      #if os(macOS)
        .navigationSubtitle(subtitle(for: item))
      #endif
      .onAppear { name = item.name }
    }
  }

  /// Where the item lives, and for folders how many items they hold.
  private func subtitle(for item: LibraryItem) -> String {
    let folder = library.parent(of: itemID).flatMap(library.item)?.name ?? "Top Level"
    guard let children = item.children else { return folder }
    return "\(folder) · \(children.count == 1 ? "1 item" : "\(children.count) items")"
  }

  private var nameField: some View {
    TextField("Name", text: $name)
      .onSubmit { library.rename(itemID, to: name) }
      .accessibilityIdentifier("detail-name")
  }
}
