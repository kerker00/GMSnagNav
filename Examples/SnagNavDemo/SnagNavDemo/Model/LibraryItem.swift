import Foundation

/// An element of the demo library: either a folder that can hold other items, or a document.
///
/// This is the demo app's *own* model. GMSnagNav never sees this type's semantics — it only reads
/// the `id` and the `children` key path.
struct LibraryItem: Identifiable, Hashable, Sendable {
  enum Kind: Hashable, Sendable {
    case folder
    case document
  }

  let id: UUID
  var name: String
  var kind: Kind
  /// The children of a folder; always `nil` for documents, which can never contain items.
  var children: [LibraryItem]?

  static func folder(_ name: String, _ children: [LibraryItem] = []) -> LibraryItem {
    LibraryItem(id: UUID(), name: name, kind: .folder, children: children)
  }

  static func document(_ name: String) -> LibraryItem {
    LibraryItem(id: UUID(), name: name, kind: .document, children: nil)
  }

  var isFolder: Bool { kind == .folder }

  /// A copy with new identifiers for the item and everything inside it.
  func copy() -> LibraryItem {
    LibraryItem(id: UUID(), name: name, kind: kind, children: children?.map { $0.copy() })
  }

  var systemImage: String {
    switch kind {
    case .folder: "folder"
    case .document: "doc.text"
    }
  }
}
