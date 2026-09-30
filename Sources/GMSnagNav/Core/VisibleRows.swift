/// A row that is currently visible in an outline, i.e. every ancestor of it is expanded.
struct VisibleRow<ID: Hashable>: Hashable {
  /// The identifier of the element shown in this row.
  let id: ID
  /// The nesting level used for indentation; root elements have a depth of `0`.
  let depth: Int
  /// The identifier of the parent element, or `nil` for a root element.
  let parent: ID?
  /// The position of the element among its siblings.
  let index: Int
  /// Whether the element can have children, even if it currently has none.
  let isExpandable: Bool
  /// Whether the element is expanded; always `false` for elements that are not expandable.
  let isExpanded: Bool
  /// The number of children of the element; `0` for leaves and empty containers.
  let childCount: Int
}

extension OutlineTree {
  /// Returns the rows that are visible for the given expansion state, in display order.
  ///
  /// An element is visible when all of its ancestors are expanded. Identifiers in `expanded` that
  /// are unknown or not expandable are ignored, so a host can keep persisted expansion state for
  /// elements that were removed in the meantime.
  func visibleRows(expanded: Set<ID>) -> [VisibleRow<ID>] {
    var rows: [VisibleRow<ID>] = []
    // A stack of sibling lists still to be emitted; each list is consumed front to back.
    var stack: [(ids: [ID], position: Int)] = [(roots, 0)]

    while let top = stack.indices.last {
      guard stack[top].position < stack[top].ids.count else {
        stack.removeLast()
        continue
      }
      let id = stack[top].ids[stack[top].position]
      stack[top].position += 1
      guard let node = node(id) else { continue }

      let children = node.children ?? []
      let isExpanded = node.children != nil && expanded.contains(id)
      rows.append(
        VisibleRow(
          id: id, depth: node.depth, parent: node.parent, index: node.index,
          isExpandable: node.children != nil, isExpanded: isExpanded,
          childCount: children.count))

      if isExpanded, !children.isEmpty {
        stack.append((children, 0))
      }
    }
    return rows
  }
}
