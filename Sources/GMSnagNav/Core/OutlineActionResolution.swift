/// Reasons an explicit action cannot reach the host's performer.
enum OutlineActionFailure: Error, Equatable {
  case sourceUnavailable, targetUnavailable, unavailable, rejected
}

extension OutlineDropHandler {
  /// Explicit commands are atomic and constrain the host's answer to their advertised meaning.
  func resolveAction<Element: Identifiable>(
    sources: [ID], target: OutlineDropTarget<ID>, operation: OutlineDropOperation,
    tree: OutlineTree<Element>, expanded: Set<ID>, isPinned: ((Element) -> Bool)?,
    exactTarget: Bool = false
  ) -> Result<OutlineDropProposal<ID>, OutlineActionFailure> where Element.ID == ID {
    guard !sources.isEmpty,
      sources.allSatisfy({ id in
        guard let element = tree.element(id) else { return false }
        return isPinned?(element) != true
      }), tree.normalizedSources(sources).count == sources.count
    else { return .failure(.sourceUnavailable) }
    guard tree.isValidDropTarget(target),
      target.parent.map(tree.isExpandable) ?? true
    else { return .failure(.targetUnavailable) }
    guard
      let resolved = resolve(
        draggedIDs: sources, target: target, tree: tree, expanded: expanded,
        isCopyRequested: operation == .copy, isPinned: isPinned),
      resolved.operation == operation,
      Set(resolved.proposal.draggedIDs) == Set(sources),
      resolved.proposal.target.parent == target.parent,
      !exactTarget || resolved.proposal.target == target,
      operation == .copy || !resolved.proposal.isDroppingIntoOwnSubtree
    else { return .failure(.rejected) }
    return .success(resolved.proposal)
  }
}
