import SwiftUI

extension SnagOutline {
  /// Sets whether the outline reveals elements that your app selects.
  ///
  /// When your app changes the selection binding — after adding an element, from a link, or with
  /// a selection restored at launch — the outline expands the collapsed containers above the
  /// newly selected element and scrolls it into view, like "Reveal in Project Navigator" in Xcode.
  /// The expanded containers are added to the expansion binding. Of several newly selected
  /// elements, the first in display order is revealed. Selections the user makes in the outline
  /// are visible already and are left alone.
  /// A newer selection or explicit navigation request cancels pending automatic reveal work.
  ///
  /// Revealing is on by default. Turn it off to keep the expansion exactly as the user left it.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter reveals: Whether to reveal elements the app selects.
  public func outlineRevealsSelection(_ reveals: Bool) -> Self {
    var copy = self
    copy.behavior.revealsSelection = reveals
    return copy
  }
}

/// Owns deferred expansion writes for one mounted outline and one current selection intent.
@MainActor
final class OutlineSelectionReveal<ID: Hashable & Sendable> {
  private var state = SelectionReveal<ID>()
  private var task: Task<Void, Never>?
  private var token = UUID()
  private var scheduledAncestors: [ID] = []

  var pending: ID? { state.pending }

  deinit { task?.cancel() }

  func settled() async { await task?.value }

  private func cancelExpansion() {
    task?.cancel()
    task = nil
    token = UUID()
    scheduledAncestors = []
  }

  func cancel() {
    cancelExpansion()
    state.didReveal()
  }

  func didReveal() { cancel() }

  func userSelected(_ ids: Set<ID>) {
    cancelExpansion()
    state.userSelected(ids)
  }

  /// Reacts to the host's selection: records it and, if `reveals` is on, adds the collapsed
  /// ancestors of a newly selected element to the expansion binding.
  ///
  /// The binding changes after the current update, since SwiftUI does not allow changing state
  /// while it updates a view. The next update expands the rows; the renderer then scrolls to
  /// ``pending``.
  func hostSelected<Element: Identifiable>(
    _ ids: Set<ID>, in tree: OutlineTree<Element>, expansion: Binding<Set<ID>>, reveals: Bool
  ) where Element.ID == ID {
    let previous = state.pending
    _ = state.hostSelected(ids, in: tree, expanded: expansion.wrappedValue)
    guard reveals, let target = state.pending, tree.contains(target) else {
      cancel()
      return
    }
    // A same-selection structure update may move the target to different ancestors.
    let ancestors = tree.ancestorsToReveal(target, expanded: expansion.wrappedValue)
    if target != previous || ancestors != scheduledAncestors { cancelExpansion() }
    guard !ancestors.isEmpty, task == nil else { return }
    let request = token
    scheduledAncestors = ancestors
    task = Task { @MainActor [weak self] in
      guard !Task.isCancelled, let self, self.token == request, self.state.pending == target
      else { return }
      self.task = nil
      self.scheduledAncestors = []
      expansion.wrappedValue.formUnion(ancestors)
    }
  }
}
