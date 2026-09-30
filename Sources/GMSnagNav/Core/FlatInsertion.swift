extension OutlineTree where ID: Sendable {
  /// Converts an insertion point in a flat list of visible rows into a drop target.
  ///
  /// Flat lists, such as a SwiftUI `List` with `onMove`, report a gap between two rows:
  /// `gap == 0` is above the first row and `gap == rows.count` below the last one. A gap is
  /// ambiguous when the row above is deeper than the row below — the items could go to the end of
  /// the deeper level or before the row below. The rule follows the row *above*, so items dragged
  /// to the bottom of an expanded folder stay in it:
  ///
  /// - Directly below an expanded element with children, the items become its first children.
  /// - Otherwise a gap inserts right *after the row above it*, at that row's level. The gap below
  ///   the last row therefore appends to the last row's level.
  /// - The gap above the first row inserts at the top of the root level.
  ///
  /// To insert before a shallower row that directly follows an expanded folder, collapse the
  /// folder first.
  ///
  /// - Parameters:
  ///   - gap: The insertion point; values outside `0...rows.count` are clamped.
  ///   - rows: The visible rows, as returned by ``visibleRows(expanded:)`` for this tree.
  func dropTarget(forGap gap: Int, in rows: [VisibleRow<ID>]) -> OutlineDropTarget<ID> {
    let gap = min(max(gap, 0), rows.count)
    guard gap > 0 else {
      return .insert(into: nil, at: 0)
    }
    let above = rows[gap - 1]
    if above.isExpanded, above.childCount > 0 {
      return .insert(into: above.id, at: 0)
    }
    return .insert(into: above.parent, at: above.index + 1)
  }
}
