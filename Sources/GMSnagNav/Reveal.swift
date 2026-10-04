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

extension SelectionReveal where ID: Sendable {
  /// Reacts to the host's selection: records it and, if `reveals` is on, adds the collapsed
  /// ancestors of a newly selected element to the expansion binding.
  ///
  /// The binding changes after the current update, since SwiftUI does not allow changing state
  /// while it updates a view. The next update expands the rows; the renderer then scrolls to
  /// ``pending``.
  @MainActor mutating func hostSelected<Element: Identifiable>(
    _ ids: Set<ID>, in tree: OutlineTree<Element>, expansion: Binding<Set<ID>>, reveals: Bool
  ) where Element.ID == ID {
    let ancestors = hostSelected(ids, in: tree, expanded: expansion.wrappedValue)
    guard reveals else {
      didReveal()
      return
    }
    guard !ancestors.isEmpty else { return }
    Task { @MainActor in
      expansion.wrappedValue.formUnion(ancestors)
    }
  }
}
