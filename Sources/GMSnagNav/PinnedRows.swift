import SwiftUI

extension SnagOutline {
  /// Keeps designated rows at the beginning of their sibling list.
  ///
  /// Pinned elements cannot be dragged or reordered with the keyboard or VoiceOver. Insertions
  /// before or between pinned siblings move behind the last pinned sibling, including copies.
  /// The host validates the adjusted proposal and receives its final insertion index.
  ///
  /// Put pinned elements first in your data: this modifier never sorts or changes your model.
  /// Pinning is relative to siblings, not the scroll position; a pinned row scrolls normally,
  /// and moving its ancestor carries it along with the rest of that subtree.
  /// Selection, expansion, renaming, deletion and drops onto containers keep their usual rules.
  /// Protect model changes made outside the outline in your own code.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter isPinned: Whether an element has a fixed position among its siblings.
  public func outlinePinned(_ isPinned: @escaping (Element) -> Bool) -> Self {
    var copy = self
    copy.behavior.isPinned = isPinned
    return copy
  }
}

extension OutlineBehavior {
  /// Track observable pin state in the SwiftUI body, including changes without a new host tree.
  func resolvingPinnedRows(in tree: OutlineTree<Element>) -> Self {
    guard let isPinned else { return self }
    var pinned: Set<Element.ID> = []
    var pending = tree.roots
    while let id = pending.popLast() {
      if let element = tree.element(id), isPinned(element) { pinned.insert(id) }
      pending.append(contentsOf: tree.children(of: id))
    }
    var copy = self
    copy.liveIsPinned = isPinned
    copy.isPinned = { pinned.contains($0.id) }
    return copy
  }
}

extension OutlineTree where ID: Sendable {
  /// Reserves the span through the last pinned sibling, even if the host interleaves normal rows.
  func targetAfterPinnedRows(
    _ target: OutlineDropTarget<ID>, isPinned: ((Element) -> Bool)?
  ) -> OutlineDropTarget<ID> {
    guard let isPinned, let index = target.childIndex,
      let lastPinned = children(of: target.parent).lastIndex(where: { id in
        element(id).map(isPinned) == true
      }), index <= lastPinned
    else { return target }
    return .insert(into: target.parent, at: lastPinned + 1)
  }
}
