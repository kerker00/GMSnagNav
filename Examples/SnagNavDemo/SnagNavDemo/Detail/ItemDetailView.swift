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
          TextField("Name", text: $name)
            .onSubmit { library.rename(itemID, to: name) }
            .accessibilityIdentifier("detail-name")
          LabeledContent("Kind", value: item.isFolder ? "Folder" : "Document")
          LabeledContent("Location", value: library.path(to: itemID).joined(separator: " › "))
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
      .onChange(of: itemID, initial: true) { name = item.name }
    }
  }
}
