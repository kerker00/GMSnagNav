import SwiftUI

extension SnagOutline {
  /// Lets the user drag elements to move them within the outline.
  ///
  /// Dragging is off by default. Dragged elements travel as in-process references, so element
  /// identifiers do not have to be `Codable`; drops from other apps or other outlines are not
  /// accepted. Handle drops with ``onOutlineDrop(validate:perform:)``.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter canDrag: Returns whether an element can be dragged. When several rows are
  ///   dragged together, only the draggable ones are included.
  public func outlineDraggable(_ canDrag: @escaping (Element) -> Bool = { _ in true }) -> Self {
    var copy = self
    copy.behavior.canDrag = canDrag
    return copy
  }

  /// Handles elements dropped onto the outline.
  ///
  /// While the user drags, `validate` is called repeatedly with the current ``OutlineDropProposal``
  /// and decides whether the drop is allowed, and where: return ``OutlineDropResult/reject`` to
  /// refuse it, ``OutlineDropResult/accept(_:)`` to allow it, or
  /// ``OutlineDropResult/redirect(to:operation:)`` to show and perform it somewhere else. When the
  /// user releases the mouse or finger, `perform` receives the final proposal — with a redirected
  /// target already applied — and the accepted operation, and changes the host's data.
  ///
  /// GMSnagNav never changes the data itself. After `perform` updates the model, the outline
  /// animates the rows to their new place.
  ///
  /// Both callbacks receive normalized ``OutlineDropProposal/draggedIDs``: only top-level elements
  /// in display order, so a descendant dragged together with its ancestor is not moved twice.
  ///
  /// ```swift
  /// .outlineDraggable()
  /// .onOutlineDrop { proposal in
  ///   proposal.isDroppingIntoOwnSubtree ? .reject : .accept(.move)
  /// } perform: { proposal, _ in
  ///   library.move(proposal.draggedIDs, into: proposal.target.parent,
  ///                at: proposal.insertionIndexAfterRemoval)
  /// }
  /// ```
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameters:
  ///   - validate: Decides whether and where a proposed drop is allowed. Keep it fast; it runs on
  ///     every pointer movement. By default, drops into a dragged element's own subtree are
  ///     rejected and everything else is accepted as a move.
  ///   - perform: Changes the host's data for an accepted drop and returns whether it succeeded.
  public func onOutlineDrop(
    validate: @escaping (OutlineDropProposal<ID>) -> OutlineDropResult<ID> = { proposal in
      proposal.isDroppingIntoOwnSubtree ? .reject : .accept(.move)
    },
    perform: @escaping (OutlineDropProposal<ID>, OutlineDropOperation) -> Bool
  ) -> Self {
    var copy = self
    copy.behavior.drop = OutlineDropHandler(validate: validate, perform: perform)
    return copy
  }
}

/// The host's drop callbacks.
struct OutlineDropHandler<ID: Hashable & Sendable> {
  let validate: (OutlineDropProposal<ID>) -> OutlineDropResult<ID>
  let perform: (OutlineDropProposal<ID>, OutlineDropOperation) -> Bool
}

extension OutlineDropHandler {
  /// Asks the host whether and where dragged elements may be dropped at a proposed target.
  ///
  /// Shared by both renderers, so validation and redirects behave the same on every platform.
  ///
  /// - Returns: The proposal — with a redirected target if the host asked for one — and the
  ///   accepted operation, or `nil` if the drop is not allowed.
  func resolve<Element: Identifiable>(
    draggedIDs: [ID], target: OutlineDropTarget<ID>, tree: OutlineTree<Element>,
    expanded: Set<ID>
  ) -> (proposal: OutlineDropProposal<ID>, operation: OutlineDropOperation)?
  where Element.ID == ID {
    let proposal = OutlineDropProposal(
      draggedIDs: draggedIDs, target: target, tree: tree, expanded: expanded)
    guard !proposal.draggedIDs.isEmpty else { return nil }

    switch validate(proposal) {
    case .reject:
      return nil
    case .accept(let operation):
      return (proposal, operation)
    case .redirect(let redirected, let operation):
      guard tree.isValidDropTarget(redirected) else { return nil }
      let proposal = OutlineDropProposal(
        draggedIDs: draggedIDs, target: redirected, tree: tree, expanded: expanded)
      return (proposal, operation)
    }
  }
}

extension OutlineTree where ID: Sendable {
  /// Whether a drop target refers to an existing parent and an index within its children.
  func isValidDropTarget(_ target: OutlineDropTarget<ID>) -> Bool {
    if let parent = target.parent, !contains(parent) { return false }
    guard let childIndex = target.childIndex else { return true }
    return (0...children(of: target.parent).count).contains(childIndex)
  }
}
