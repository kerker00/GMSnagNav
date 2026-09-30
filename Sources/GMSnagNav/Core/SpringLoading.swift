extension OutlineTree {
  /// Returns the spring-loaded elements that should close again for the current drop target.
  ///
  /// While dragging, hovering over a collapsed element opens it temporarily. Such an element stays
  /// open while the drop target lies inside it — onto it, or anywhere in its subtree — and closes
  /// once the pointer moves elsewhere, like spring-loaded folders in the Finder.
  ///
  /// - Parameters:
  ///   - springLoaded: The elements opened by spring-loading during the current drag.
  ///   - targetParent: The parent of the current drop target, or `nil` for the root level or when
  ///     no drop target is proposed.
  /// - Returns: The elements to close, deepest first.
  func springLoadedToClose(_ springLoaded: [ID], targetParent: ID?) -> [ID] {
    let keep = Set([targetParent].compactMap { $0 } + (targetParent.map(ancestors(of:)) ?? []))
    return springLoaded.filter { !keep.contains($0) }
      .sorted { (node($0)?.depth ?? 0) > (node($1)?.depth ?? 0) }
  }
}
