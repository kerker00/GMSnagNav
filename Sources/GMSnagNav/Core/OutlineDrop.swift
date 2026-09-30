/// Where dragged items would land in an outline.
///
/// A drop either lands *onto* an element — the items become its children, typically appended — or
/// is *inserted* at an exact position among the children of an element. For both, a `parent` of
/// `nil` stands for the root level of the outline.
public struct OutlineDropTarget<ID: Hashable & Sendable>: Hashable, Sendable {
  /// How the dropped items are placed relative to ``parent``.
  public enum Placement: Hashable, Sendable {
    /// The items are dropped onto the parent itself; the host decides where they go among its
    /// children, usually at the end.
    case onto
    /// The items are inserted before the child at `childIndex`; an index equal to the number of
    /// children inserts after the last child.
    ///
    /// The index refers to the children *before* the dragged items are removed from their current
    /// position. See ``OutlineDropProposal/insertionIndexAfterRemoval``.
    case insert(childIndex: Int)
  }

  /// The element that becomes the parent of the dropped items, or `nil` for the root level.
  public var parent: ID?

  /// How the dropped items are placed relative to ``parent``.
  public var placement: Placement

  /// Creates a drop target.
  public init(parent: ID?, placement: Placement) {
    self.parent = parent
    self.placement = placement
  }

  /// A drop onto an element; the dropped items become its children.
  public static func onto(_ element: ID) -> Self {
    Self(parent: element, placement: .onto)
  }

  /// A drop onto the empty area of the outline; the dropped items move to the root level.
  public static var root: Self {
    Self(parent: nil, placement: .onto)
  }

  /// A drop at an exact position among the children of `parent`, or of the root level for `nil`.
  public static func insert(into parent: ID?, at childIndex: Int) -> Self {
    Self(parent: parent, placement: .insert(childIndex: childIndex))
  }

  /// The insertion index for ``Placement/insert(childIndex:)`` drops, or `nil` for
  /// ``Placement/onto`` drops.
  public var childIndex: Int? {
    guard case .insert(let childIndex) = placement else { return nil }
    return childIndex
  }
}

/// What a drop does with the dragged items.
public enum OutlineDropOperation: Hashable, Sendable {
  /// The items are moved to the target.
  case move
  /// Copies of the items are added at the target; the originals stay where they are.
  case copy
}

/// A host's answer to a proposed drop.
public enum OutlineDropResult<ID: Hashable & Sendable>: Hashable, Sendable {
  /// The drop is not allowed; the outline shows no drop indicator.
  case reject
  /// The drop is allowed at the proposed target with the given operation.
  case accept(OutlineDropOperation)
  /// The drop is allowed, but at a different target than proposed — for example onto a folder
  /// instead of between two of its children. The outline shows the indicator at the new target,
  /// and the drop is performed there.
  case redirect(to: OutlineDropTarget<ID>, operation: OutlineDropOperation)
}

/// A drop that the user is about to perform, passed to the host for validation and execution.
///
/// GMSnagNav never changes the host's data. It describes *what* is dragged and *where* it would
/// land; the host checks whether that is allowed and performs the change in its own model.
public struct OutlineDropProposal<ID: Hashable & Sendable>: Hashable, Sendable {
  /// The identifiers of the dragged elements, in display order and without duplicates.
  public let draggedIDs: [ID]

  /// Where the dragged elements would land.
  public let target: OutlineDropTarget<ID>

  /// Whether the target's parent element is currently expanded; `false` for the root level.
  ///
  /// Useful to decide, for example, whether a drop onto a collapsed folder should append or
  /// prepend its items.
  public let isTargetExpanded: Bool

  /// Whether the target lies inside one of the dragged elements, or is one of them.
  ///
  /// Moving an element into its own subtree would create a cycle; most hosts reject such drops.
  public let isDroppingIntoOwnSubtree: Bool

  /// The insertion index adjusted for the dragged elements being removed first, or `nil` for
  /// ``OutlineDropTarget/Placement/onto`` drops.
  ///
  /// ``OutlineDropTarget/childIndex`` counts the dragged elements that currently sit before the
  /// insertion point among the same siblings. Hosts that remove the dragged elements before
  /// inserting them — the usual way to implement a move — should insert at this index instead.
  public let insertionIndexAfterRemoval: Int?

  /// Creates a proposal, for example to unit test a host's drop validation.
  public init(
    draggedIDs: [ID],
    target: OutlineDropTarget<ID>,
    isTargetExpanded: Bool = false,
    isDroppingIntoOwnSubtree: Bool = false,
    insertionIndexAfterRemoval: Int? = nil
  ) {
    self.draggedIDs = draggedIDs
    self.target = target
    self.isTargetExpanded = isTargetExpanded
    self.isDroppingIntoOwnSubtree = isDroppingIntoOwnSubtree
    self.insertionIndexAfterRemoval = insertionIndexAfterRemoval ?? target.childIndex
  }
}

extension OutlineDropProposal {
  /// Creates a proposal from the outline's current snapshot.
  init<Element: Identifiable>(
    draggedIDs: [ID], target: OutlineDropTarget<ID>, tree: OutlineTree<Element>,
    expanded: Set<ID>
  ) where Element.ID == ID {
    var seen: Set<ID> = []
    let unique = draggedIDs.filter { tree.contains($0) && seen.insert($0).inserted }
    let dragged = unique.sorted {
      tree.indexPath(of: $0).lexicographicallyPrecedes(tree.indexPath(of: $1))
    }

    let intoOwnSubtree: Bool
    if let parent = target.parent {
      intoOwnSubtree = dragged.contains { $0 == parent || tree.isDescendant(parent, of: $0) }
    } else {
      intoOwnSubtree = false
    }

    var adjustedIndex = target.childIndex
    if let childIndex = target.childIndex {
      let removedBefore = dragged.filter { id in
        guard let node = tree.node(id) else { return false }
        return node.parent == target.parent && node.index < childIndex
      }
      adjustedIndex = childIndex - removedBefore.count
    }

    self.init(
      draggedIDs: dragged,
      target: target,
      isTargetExpanded: target.parent.map(expanded.contains) ?? false,
      isDroppingIntoOwnSubtree: intoOwnSubtree,
      insertionIndexAfterRemoval: adjustedIndex)
  }
}
