import SwiftUI

extension SnagOutline {
  /// Adds actions that appear when the user swipes a row on iOS and iPadOS, like deleting a
  /// message in Mail.
  ///
  /// The closure receives the swiped element and returns the actions to show, from the edge
  /// inwards; return none to allow no swipe on that row. Only ``OutlineMenuItem/action(_:systemImage:role:isDisabled:perform:)``
  /// items take part: submenus, dividers and disabled actions are left out. A destructive role
  /// shows the action in red.
  ///
  /// Swiping is a touch gesture, so macOS shows no swipe actions; offer the same actions in a
  /// context menu there, and on iOS as well for people who don't swipe.
  ///
  /// ```swift
  /// .outlineSwipeActions { id in
  ///   [.action("Delete", systemImage: "trash", role: .destructive) { library.delete(id) }]
  /// }
  /// ```
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameters:
  ///   - edge: The edge the actions appear at: `.trailing` when swiping to the left, `.leading`
  ///     when swiping to the right.
  ///   - allowsFullSwipe: Whether swiping all the way across performs the first action.
  ///   - actions: Builds the actions for the swiped element.
  public func outlineSwipeActions(
    edge: HorizontalEdge = .trailing, allowsFullSwipe: Bool = true,
    _ actions: @escaping @MainActor (ID) -> [OutlineMenuItem]
  ) -> Self {
    var copy = self
    let swipe = OutlineSwipeActions(actions: actions, allowsFullSwipe: allowsFullSwipe)
    switch edge {
    case .leading: copy.behavior.leadingSwipeActions = swipe
    case .trailing: copy.behavior.trailingSwipeActions = swipe
    }
    return copy
  }
}

/// The swipe actions for one edge of the rows.
struct OutlineSwipeActions<ID> {
  let actions: @MainActor (ID) -> [OutlineMenuItem]
  let allowsFullSwipe: Bool
}
