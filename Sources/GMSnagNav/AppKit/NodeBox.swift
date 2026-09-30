#if os(macOS)
  import AppKit

  /// The item object handed to `NSOutlineView` for one element.
  ///
  /// `NSOutlineView` tracks expansion and selection per item object. Boxes are cached per
  /// identifier and reused across updates, so the outline keeps its state when the host's values
  /// change; equality and hashing follow the identifier for the lookups AppKit performs by value.
  final class NodeBox<ID: Hashable>: NSObject {
    let id: ID

    init(_ id: ID) {
      self.id = id
    }

    override var hash: Int { id.hashValue }

    override func isEqual(_ object: Any?) -> Bool {
      (object as? NodeBox<ID>)?.id == id
    }

    override var debugDescription: String { "NodeBox(\(id))" }
  }
#endif
