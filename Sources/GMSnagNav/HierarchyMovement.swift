import SwiftUI

extension SnagOutline {
  /// Offers moving one row into its previous sibling container or out after its parent.
  ///
  /// Command-Option-Forward indents and Command-Option-Backward outdents, mirrored in RTL.
  /// VoiceOver offers the same operations on each eligible row. Keyboard commands require
  /// one visible selected or focused row. Editors keep their shortcuts; active renaming blocks
  /// movement. Section boundaries are not crossed automatically.
  ///
  /// Requires `onOutlineDrop`; only a move to the exact calculated position is accepted.
  /// Dragging and sibling reordering are separate opt-ins. Disable this behavior for filtered
  /// or sorted displays whose order differs from the model's mutation indices.
  ///
  /// - Parameters:
  ///   - keyboardShortcuts: Whether to handle modified horizontal arrows, independently of AX.
  ///   - canMove: Reads current host eligibility for an element; all rows by default.
  public func outlineHierarchyMovable(
    keyboardShortcuts: Bool = true, _ canMove: @escaping (Element) -> Bool = { _ in true }
  ) -> Self {
    var copy = self
    copy.behavior.canMoveHierarchy = canMove
    copy.behavior.hierarchyKeyboardShortcuts = keyboardShortcuts
    return copy
  }
}

extension OutlineBehavior {
  /// Observe dependencies in body without replacing the live predicates used during execution.
  func observingHierarchy(in tree: OutlineTree<Element>) -> Self {
    guard let canMoveHierarchy else { return self }
    var pending = tree.roots
    while let id = pending.popLast() {
      if let element = tree.element(id) { _ = canMoveHierarchy(element) }
      pending.append(contentsOf: tree.children(of: id))
    }
    return self
  }

  @MainActor func hierarchyProposal(
    for id: Element.ID, direction: OutlineHierarchyDirection,
    tree fallback: OutlineTree<Element>, expanded: Set<Element.ID>, readsLiveData: Bool = true
  ) -> OutlineDropProposal<Element.ID>? {
    guard let canMoveHierarchy, let drop, renaming?.renaming.wrappedValue == nil else { return nil }
    // Display eligibility shares the renderer snapshot; execution rechecks the live model.
    let tree = readsLiveData ? (actionTree?() ?? fallback) : fallback
    guard let element = tree.element(id), canMoveHierarchy(element),
      let target = tree.hierarchyTarget(
        for: id, direction: direction, isSection: { sectionTitle(of: $0, in: tree) != nil })
    else { return nil }
    guard
      case .success(let proposal) = drop.resolveAction(
        sources: [id], target: target, operation: .move, tree: tree, expanded: expanded,
        isPinned: liveIsPinned ?? isPinned, exactTarget: true)
    else { return nil }
    return proposal
  }
}

/// Defers binding writes and scrolling until a renderer receives the changed host structure.
@MainActor
final class OutlineHierarchyReveal<ID: Hashable & Sendable> {
  struct Request {
    let token = UUID()
    let source: ID
    let parent: ID?
    let selection: Set<ID>
    let preservesKeyboardFocus: Bool
  }

  private var pending: Request?
  private var task: Task<Void, Never>?

  func record(_ proposal: OutlineDropProposal<ID>, selection: Set<ID>, focused: Bool) {
    cancel()
    guard let source = proposal.draggedIDs.first else { return }
    pending = Request(
      source: source, parent: proposal.target.parent, selection: selection,
      preservesKeyboardFocus: focused)
  }

  func cancel() {
    task?.cancel()
    task = nil
    pending = nil
  }

  func settled() async { await task?.value }

  func update<Element: Identifiable>(
    tree: OutlineTree<Element>, previous: OutlineTree<Element>, selection: Set<ID>,
    navigationPending: Bool, reveal: @escaping (Request) -> Void
  ) where Element.ID == ID {
    guard let request = pending else { return }
    guard !navigationPending, selection == request.selection, tree.contains(request.source) else {
      cancel()
      return
    }
    // The expected host update may schedule a reveal. A later structural update supersedes it,
    // even if the source still has the expected parent when the deferred task eventually runs.
    if task != nil, !tree.hasSameStructure(as: previous) {
      cancel()
      return
    }
    guard tree.parent(of: request.source) == request.parent else {
      if !tree.hasSameStructure(as: previous) { cancel() }
      return
    }
    guard task == nil else { return }
    task = Task { @MainActor [weak self] in
      guard !Task.isCancelled, let self, self.pending?.token == request.token else { return }
      self.pending = nil
      self.task = nil
      reveal(request)
    }
  }
}
