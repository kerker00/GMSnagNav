/// Reasons an explicit action cannot reach the host's performer.
enum OutlineActionFailure: Error, Equatable {
  case sourceUnavailable, targetUnavailable, rejected
}

extension OutlineDropHandler {
  /// Explicit commands are atomic and constrain the host's answer to their advertised meaning.
  func resolveAction<Element: Identifiable>(
    sources: [ID], target: OutlineDropTarget<ID>, operation: OutlineDropOperation,
    tree: OutlineTree<Element>, expanded: Set<ID>, isPinned: ((Element) -> Bool)?,
    preparation: OutlineActionPreparation<Element>? = nil
  ) -> Result<OutlineDropProposal<ID>, OutlineActionFailure> where Element.ID == ID {
    let sourcesAvailable =
      preparation?.sourcesAvailable
      ?? (!sources.isEmpty
        && sources.allSatisfy({ id in
          guard let element = tree.element(id) else { return false }
          return isPinned?(element) != true
        }) && tree.normalizedSources(sources).count == sources.count)
    guard sourcesAvailable else { return .failure(.sourceUnavailable) }
    guard tree.isValidDropTarget(target),
      target.parent.map(tree.isExpandable) ?? true
    else { return .failure(.targetUnavailable) }
    let resolution: (proposal: OutlineDropProposal<ID>, operation: OutlineDropOperation)?
    if let preparation {
      resolution = resolve(target: target, tree: tree, isPinned: isPinned) {
        preparation.proposal(at: $0, operation: operation)
      }
    } else {
      resolution = resolve(
        draggedIDs: sources, target: target, tree: tree, expanded: expanded,
        isCopyRequested: operation == .copy, isPinned: isPinned)
    }
    guard let resolved = resolution,
      resolved.operation == operation,
      preparation != nil || Set(resolved.proposal.draggedIDs) == Set(sources),
      resolved.proposal.target.parent == target.parent,
      operation == .copy || !resolved.proposal.isDroppingIntoOwnSubtree
    else { return .failure(.rejected) }
    return .success(resolved.proposal)
  }
}

/// Source checks and subtree membership shared by all destinations of one immutable menu snapshot.
/// Execution still resolves afresh against the live model; this value never escapes into actions.
struct OutlineActionPreparation<Element: Identifiable> where Element.ID: Sendable {
  typealias ID = Element.ID
  let sources: [ID]
  let sourcesAvailable: Bool
  private let tree: OutlineTree<Element>
  private let expanded: Set<ID>
  private let ownSubtree: Set<ID>

  init(
    sources: [ID], tree: OutlineTree<Element>, expanded: Set<ID>, isPinned: (Element) -> Bool
  ) {
    self.sources = sources
    self.tree = tree
    self.expanded = expanded
    sourcesAvailable =
      !sources.isEmpty
      && sources.allSatisfy {
        tree.element($0).map { !isPinned($0) } == true
      }
    var blocked: Set<ID> = []
    var pending = sources
    while let id = pending.popLast() {
      guard blocked.insert(id).inserted else { continue }
      pending.append(contentsOf: tree.children(of: id))
    }
    ownSubtree = blocked
  }

  func proposal(at target: OutlineDropTarget<ID>, operation: OutlineDropOperation)
    -> OutlineDropProposal<ID>
  {
    let adjustedIndex = target.childIndex.map { index in
      index
        - sources.filter {
          guard let node = tree.node($0) else { return false }
          return node.parent == target.parent && node.index < index
        }.count
    }
    return OutlineDropProposal(
      draggedIDs: sources, target: target,
      isTargetExpanded: target.parent.map(expanded.contains) ?? false,
      isDroppingIntoOwnSubtree: target.parent.map(ownSubtree.contains) ?? false,
      insertionIndexAfterRemoval: adjustedIndex, isCopyRequested: operation == .copy)
  }
}
