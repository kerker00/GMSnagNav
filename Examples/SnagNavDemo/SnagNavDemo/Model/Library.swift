import Foundation
import GMSnagNav
import Observation

/// The demo app's store: the single source of truth for the tree and every mutation of it.
///
/// This is the part a host app always owns. GMSnagNav reports *what* was dropped *where*; deciding
/// whether that is allowed and performing the change happens here — exactly like a Core Data or
/// SwiftData store would do it in a real app.
@Observable
final class Library {
  enum MoveError: LocalizedError {
    case itemNotFound
    case targetIsNotAFolder
    case wouldCreateCycle

    var errorDescription: String? {
      switch self {
      case .itemNotFound: "The item no longer exists."
      case .targetIsNotAFolder: "Items can only be moved into folders."
      case .wouldCreateCycle: "A folder cannot be moved into itself or one of its subfolders."
      }
    }
  }

  private(set) var roots: [LibraryItem]

  init(roots: [LibraryItem] = Library.sample) {
    self.roots = roots
  }

  // MARK: Queries

  func item(_ id: LibraryItem.ID) -> LibraryItem? {
    Self.find(id, in: roots)
  }

  /// The folder that contains the item, or `nil` at the root level.
  func parent(of id: LibraryItem.ID) -> LibraryItem.ID? {
    Self.location(of: id, in: roots)?.parent
  }

  /// The names from the root down to the item, e.g. `["Work", "Clients", "Brief.md"]`.
  func path(to id: LibraryItem.ID) -> [String] {
    Self.path(to: id, in: roots) ?? []
  }

  /// All folders in depth-first order with their nesting depth, for "Move to…" menus.
  var allFolders: [(item: LibraryItem, depth: Int)] {
    var result: [(LibraryItem, Int)] = []
    func visit(_ items: [LibraryItem], depth: Int) {
      for item in items where item.isFolder {
        result.append((item, depth))
        visit(item.children ?? [], depth: depth + 1)
      }
    }
    visit(roots, depth: 0)
    return result
  }

  /// Returns whether `id` may be moved into `folder` (`nil` meaning the root level).
  func canMove(_ id: LibraryItem.ID, into folder: LibraryItem.ID?) -> Bool {
    (try? validateMove(id, into: folder)) != nil
  }

  // MARK: Mutations

  /// Moves an item into a folder (or the root level for `nil`) at `index`, appending when `nil`.
  ///
  /// The index refers to the destination's children *before* the item is removed, which is how
  /// outline views report insertion points. Moving within the same parent is adjusted for that.
  func move(_ id: LibraryItem.ID, into folder: LibraryItem.ID?, at index: Int? = nil) throws {
    try validateMove(id, into: folder)
    let source = Self.location(of: id, in: roots)
    guard let item = Self.remove(id, from: &roots) else { throw MoveError.itemNotFound }

    var insertionIndex = index
    if let index, let source, source.parent == folder, source.index < index {
      insertionIndex = index - 1
    }
    Self.insert(item, into: folder, at: insertionIndex, in: &roots)
  }

  /// Moves several items into a folder (or the root level for `nil`), keeping their order.
  ///
  /// `index` refers to the destination's children *after* the items were removed — what
  /// `OutlineDropProposal.insertionIndexAfterRemoval` provides. `nil` appends.
  func move(_ ids: [LibraryItem.ID], into folder: LibraryItem.ID?, at index: Int?) throws {
    for id in ids { try validateMove(id, into: folder) }
    let items = ids.compactMap { Self.remove($0, from: &roots) }
    for (offset, item) in items.enumerated() {
      Self.insert(item, into: folder, at: index.map { $0 + offset }, in: &roots)
    }
  }

  // MARK: Drag and drop

  /// Decides whether and where a drag may be dropped — called on every pointer movement.
  func dropResult(
    for proposal: OutlineDropProposal<LibraryItem.ID>
  ) -> OutlineDropResult<LibraryItem.ID> {
    // Moving a folder into itself or one of its subfolders would create a cycle.
    if proposal.isDroppingIntoOwnSubtree { return .reject }

    guard let parent = proposal.target.parent, let target = item(parent) else {
      return .accept(.move)
    }
    if target.isFolder { return .accept(.move) }

    // Documents cannot contain items: dropping onto one inserts right after it instead.
    guard let location = Self.location(of: parent, in: roots) else { return .reject }
    return .redirect(to: .insert(into: location.parent, at: location.index + 1), operation: .move)
  }

  /// Performs an accepted drop.
  func performDrop(_ proposal: OutlineDropProposal<LibraryItem.ID>) throws {
    try move(
      proposal.draggedIDs, into: proposal.target.parent, at: proposal.insertionIndexAfterRemoval)
  }

  func rename(_ id: LibraryItem.ID, to name: String) {
    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }
    Self.update(id, in: &roots) { $0.name = trimmed }
  }

  func delete(_ id: LibraryItem.ID) {
    _ = Self.remove(id, from: &roots)
  }

  /// Adds an item to a folder (or the root level for `nil`) and returns its identifier.
  @discardableResult
  func add(_ item: LibraryItem, into folder: LibraryItem.ID?) -> LibraryItem.ID {
    let target = folder.flatMap { self.item($0)?.isFolder == true ? $0 : nil }
    Self.insert(item, into: target, at: nil, in: &roots)
    return item.id
  }

  // MARK: Validation

  private func validateMove(_ id: LibraryItem.ID, into folder: LibraryItem.ID?) throws {
    guard item(id) != nil else { throw MoveError.itemNotFound }
    guard let folder else { return }
    guard let target = item(folder) else { throw MoveError.itemNotFound }
    guard target.isFolder else { throw MoveError.targetIsNotAFolder }
    if folder == id || Self.path(to: folder, in: item(id)?.children ?? []) != nil {
      throw MoveError.wouldCreateCycle
    }
  }
}

// MARK: - Tree helpers

extension Library {
  fileprivate static func find(_ id: LibraryItem.ID, in items: [LibraryItem]) -> LibraryItem? {
    for item in items {
      if item.id == id { return item }
      if let found = find(id, in: item.children ?? []) { return found }
    }
    return nil
  }

  fileprivate static func path(to id: LibraryItem.ID, in items: [LibraryItem]) -> [String]? {
    for item in items {
      if item.id == id { return [item.name] }
      if let rest = path(to: id, in: item.children ?? []) { return [item.name] + rest }
    }
    return nil
  }

  fileprivate static func location(
    of id: LibraryItem.ID, in items: [LibraryItem], parent: LibraryItem.ID? = nil
  ) -> (parent: LibraryItem.ID?, index: Int)? {
    for (index, item) in items.enumerated() {
      if item.id == id { return (parent, index) }
      if let found = location(of: id, in: item.children ?? [], parent: item.id) { return found }
    }
    return nil
  }

  fileprivate static func remove(_ id: LibraryItem.ID, from items: inout [LibraryItem])
    -> LibraryItem?
  {
    if let index = items.firstIndex(where: { $0.id == id }) {
      return items.remove(at: index)
    }
    for index in items.indices {
      guard var children = items[index].children,
        let removed = remove(id, from: &children)
      else { continue }
      items[index].children = children
      return removed
    }
    return nil
  }

  fileprivate static func insert(
    _ item: LibraryItem, into folder: LibraryItem.ID?, at index: Int?,
    in items: inout [LibraryItem]
  ) {
    guard let folder else {
      items.insert(item, at: clamped(index, count: items.count))
      return
    }
    update(folder, in: &items) { target in
      var children = target.children ?? []
      children.insert(item, at: clamped(index, count: children.count))
      target.children = children
    }
  }

  fileprivate static func update(
    _ id: LibraryItem.ID, in items: inout [LibraryItem], _ change: (inout LibraryItem) -> Void
  ) {
    for index in items.indices {
      if items[index].id == id {
        change(&items[index])
        return
      }
      if var children = items[index].children {
        update(id, in: &children, change)
        items[index].children = children
      }
    }
  }

  private static func clamped(_ index: Int?, count: Int) -> Int {
    guard let index else { return count }
    return min(max(index, 0), count)
  }
}

// MARK: - Sample data

extension Library {
  static var sample: [LibraryItem] {
    [
      .folder(
        "Work",
        [
          .folder(
            "Clients",
            [
              .folder("Acme", [.document("Kickoff Notes"), .document("Proposal")]),
              .folder("Globex", [.document("Contract")]),
            ]),
          .folder("Internal", [.document("Roadmap"), .document("Retrospective")]),
          .document("Weekly Report"),
        ]),
      .folder(
        "Personal",
        [
          .folder("Travel", [.document("Packing List"), .document("Itinerary")]),
          .document("Recipes"),
        ]),
      .folder("Archive"),
      .document("Inbox"),
      .document("Ideas"),
    ]
  }
}
