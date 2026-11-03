enum OutlineHierarchyDirection: CaseIterable {
  case indent, outdent

  var titleKey: String {
    self == .indent ? "Move One Level Deeper" : "Move One Level Up"
  }
}

extension OutlineTree where ID: Sendable {
  /// The exact structural step, independent of visible descendants or expansion.
  func hierarchyTarget(
    for id: ID, direction: OutlineHierarchyDirection, isSection: (ID) -> Bool
  ) -> OutlineDropTarget<ID>? {
    guard let node = node(id), !isSection(id) else { return nil }
    switch direction {
    case .indent:
      guard node.index > 0 else { return nil }
      let previous = children(of: node.parent)[node.index - 1]
      guard isExpandable(previous), !isSection(previous) else { return nil }
      return .insert(into: previous, at: children(of: previous).count)
    case .outdent:
      guard let parent = node.parent, let parentNode = self.node(parent), !isSection(parent)
      else { return nil }
      return .insert(into: parentNode.parent, at: parentNode.index + 1)
    }
  }
}
