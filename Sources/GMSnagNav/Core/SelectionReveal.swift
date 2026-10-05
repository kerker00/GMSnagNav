/// Decides which element to reveal when the host changes the selection.
///
/// A selection the user makes in the outline is visible already; one the host sets — after adding
/// an element, from a link, or restored at launch — may lie inside collapsed containers or
/// outside the visible area. Renderers report both kinds of changes; for the host's, this type
/// names the ancestors to expand and remembers the element to scroll to once they are open.
struct SelectionReveal<ID: Hashable> {
  /// The selection last seen, from either side; `nil` before the first update.
  private var known: Set<ID>?

  /// The element waiting to be scrolled into view.
  private(set) var pending: ID?

  /// Records a selection the user made in the outline; it is never revealed.
  mutating func userSelected(_ ids: Set<ID>) {
    known = ids
  }

  /// Compares the host's selection with the last known one.
  ///
  /// When the host selected elements that were not selected before, the first of them in display
  /// order is remembered as ``pending``.
  ///
  /// - Returns: The collapsed ancestors of that element, root first, which must be expanded to
  ///   show it; empty when nothing needs to be expanded.
  mutating func hostSelected<Element: Identifiable>(
    _ ids: Set<ID>, in tree: OutlineTree<Element>, expanded: Set<ID>
  ) -> [ID] where Element.ID == ID {
    guard ids != known else { return [] }
    let added = known.map { ids.subtracting($0) } ?? ids
    known = ids
    guard
      let target = added.filter(tree.contains).min(by: {
        tree.indexPath(of: $0).lexicographicallyPrecedes(tree.indexPath(of: $1))
      })
    else { return [] }
    pending = target
    return tree.ancestorsToReveal(target, expanded: expanded)
  }

  /// Forgets the pending element once it was scrolled into view.
  mutating func didReveal() {
    pending = nil
  }
}
