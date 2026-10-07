import SwiftUI

extension SnagOutline {
  /// Offers moving one element up or down among its siblings without dragging.
  ///
  /// Command-Option-Up and Command-Option-Down move the single selected or focused row on macOS
  /// and iPad. VoiceOver offers the same actions on each eligible row, independently of selection.
  /// Text editors keep their shortcuts. Multiple selections are not reordered by these commands.
  ///
  /// Requires ``onOutlineDrop(validate:perform:)``: the existing validator decides whether each
  /// move is allowed and `perform` changes the host's model. The proposal uses insertion indices
  /// before removal, just like dragging. Copy results and redirects that would change the parent
  /// or requested sibling position are unavailable, rather than performing a different action.
  ///
  /// Reordering is independent of ``outlineDraggable(_:)``. Use the predicate to protect rows
  /// and disable it for filtered or sorted views whose order differs from the host's model.
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter canReorder: Whether the element may be reordered. All elements can by default.
  public func outlineReorderable(_ canReorder: @escaping (Element) -> Bool = { _ in true }) -> Self
  {
    var copy = self
    copy.behavior.canReorder = canReorder
    return copy
  }
}

enum OutlineReorderDirection {
  case up, down
}

extension OutlineBehavior {
  /// Resolves against the current snapshot without using the pointer-drag cache.
  func reorderingProposal(
    for id: Element.ID, direction: OutlineReorderDirection, tree: OutlineTree<Element>,
    expanded: Set<Element.ID>
  ) -> OutlineDropProposal<Element.ID>? {
    guard let canReorder, let drop, let node = tree.node(id), canReorder(node.element),
      renaming?.renaming.wrappedValue == nil
    else { return nil }
    let destination = node.index + (direction == .up ? -1 : 1)
    guard tree.children(of: node.parent).indices.contains(destination) else { return nil }
    let insertion = direction == .up ? destination : destination + 1
    guard
      let resolved = drop.resolve(
        draggedIDs: [id], target: .insert(into: node.parent, at: insertion),
        tree: tree, expanded: expanded),
      resolved.operation == .move,
      !resolved.proposal.isDroppingIntoOwnSubtree,
      resolved.proposal.target.parent == node.parent,
      resolved.proposal.insertionIndexAfterRemoval == destination
    else { return nil }
    return resolved.proposal
  }

  /// Revalidates before executing, so a stale VoiceOver action cannot bypass host rules.
  @discardableResult func reorder(
    _ id: Element.ID, direction: OutlineReorderDirection, tree: OutlineTree<Element>,
    expanded: Set<Element.ID>
  ) -> Bool {
    guard
      let proposal = reorderingProposal(
        for: id, direction: direction, tree: tree, expanded: expanded), let drop
    else { return false }
    return drop.perform(proposal, .move)
  }
}

/// Keeps the same view structure while available actions change with position and host rules.
struct ReorderingAccessibility: ViewModifier {
  let canMoveUp: Bool
  let canMoveDown: Bool
  let move: (OutlineReorderDirection) -> Void

  func body(content: Content) -> some View {
    content.accessibilityActions {
      if canMoveUp {
        Button {
          move(.up)
        } label: {
          Text("Move Up", bundle: .module)
        }
      }
      if canMoveDown {
        Button {
          move(.down)
        } label: {
          Text("Move Down", bundle: .module)
        }
      }
    }
  }
}
