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
