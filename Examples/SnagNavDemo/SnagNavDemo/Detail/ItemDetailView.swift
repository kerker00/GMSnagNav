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
      .onAppear { name = item.name }
    }
  }

  private var nameField: some View {
    TextField("Name", text: $name)
      .onSubmit { library.rename(itemID, to: name) }
      .accessibilityIdentifier("detail-name")
  }
}
