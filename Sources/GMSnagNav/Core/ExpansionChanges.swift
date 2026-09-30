/// The steps that turn one expansion state into another, in an order a view can apply them.
struct ExpansionChanges<ID: Hashable>: Equatable {
  /// Elements to collapse, deepest first, so no element is hidden before it is collapsed itself.
  var collapse: [ID]
  /// Elements to expand, top-down in display order, so every element is loaded before it expands.
  var expand: [ID]

  /// Whether applying the changes would do nothing.
  var isEmpty: Bool { collapse.isEmpty && expand.isEmpty }
}

extension OutlineTree {
  /// Returns the path of sibling indices from the root level down to an element.
  ///
  /// Comparing index paths lexicographically orders elements in display (pre-order) order.
  /// Unknown identifiers return an empty path.
  func indexPath(of id: ID) -> [Int] {
    guard let node = node(id) else { return [] }
    var path = [node.index]
    for ancestor in ancestors(of: id) {
      guard let index = self.node(ancestor)?.index else { break }
      path.append(index)
    }
    return path.reversed()
  }

  /// Returns the changes needed to go from the `current` to the `desired` expansion state.
  ///
  /// Expansion is tracked per element, independent of its ancestors — like SwiftUI's
  /// `DisclosureGroup`, an element may be expanded while its parent is collapsed and appears
  /// expanded once the parent opens. Identifiers that are unknown or not expandable are ignored.
  func expansionChanges(from current: Set<ID>, to desired: Set<ID>) -> ExpansionChanges<ID> {
    let collapse = current.subtracting(desired).filter(isExpandable)
    let expand = desired.subtracting(current).filter(isExpandable)

    let collapseOrder = collapse.map { (id: $0, path: indexPath(of: $0)) }
      .sorted { lhs, rhs in
        lhs.path.count != rhs.path.count
          ? lhs.path.count > rhs.path.count
          : lhs.path.lexicographicallyPrecedes(rhs.path)
      }
    let expandOrder = expand.map { (id: $0, path: indexPath(of: $0)) }
      .sorted { $0.path.lexicographicallyPrecedes($1.path) }

    return ExpansionChanges(collapse: collapseOrder.map(\.id), expand: expandOrder.map(\.id))
  }

  /// Returns the collapsed ancestors that must be expanded to make an element visible, root first.
  ///
  /// Used to reveal a selection. Returns an empty array for root elements, for elements whose
  /// ancestors are all expanded, and for unknown identifiers.
  func ancestorsToReveal(_ id: ID, expanded: Set<ID>) -> [ID] {
    ancestors(of: id).reversed().filter { !expanded.contains($0) }
  }
}
