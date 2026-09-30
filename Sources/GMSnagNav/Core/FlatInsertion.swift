extension OutlineTree where ID: Sendable {
  /// Converts an insertion point in a flat list of visible rows into a drop target.
  ///
  /// Flat lists, such as a SwiftUI `List` with `onMove`, report a gap between two rows:
  /// `gap == 0` is above the first row and `gap == rows.count` below the last one. A gap is
  /// ambiguous when the row above is deeper than the row below — the items could go to the end of
  /// the deeper level or before the row below. The rule is deliberately simple and predictable:
  ///
  /// - A gap inserts *before the row below it*, at that row's level. Directly below an expanded
  ///   element this makes the items its first children.
  /// - The gap below the last row appends to the root level.
  ///
  /// To add items at the end of a nested level, drop them onto the parent element instead.
  ///
  /// - Parameters:
  ///   - gap: The insertion point; values outside `0...rows.count` are clamped.
  ///   - rows: The visible rows, as returned by ``visibleRows(expanded:)`` for this tree.
  func dropTarget(forGap gap: Int, in rows: [VisibleRow<ID>]) -> OutlineDropTarget<ID> {
    let gap = min(max(gap, 0), rows.count)
    guard gap < rows.count else {
      return .insert(into: nil, at: roots.count)
    }
    let below = rows[gap]
    return .insert(into: below.parent, at: below.index)
  }
}
