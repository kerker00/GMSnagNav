import SwiftUI

extension SnagOutline {
  /// Shows content in place of the rows while the outline has no elements, such as an empty
  /// library or a search without matches.
  ///
  /// The content appears centered over the outline whenever `data` is empty. It lets clicks,
  /// taps and drops through, so the user can still drop elements onto the root level and open the
  /// context menu for empty space on macOS. Controls in the content therefore do not respond;
  /// offer actions such as "New Folder" in a toolbar, a bottom bar or the context menu instead.
  ///
  /// ```swift
  /// .outlineEmptyContent {
  ///   if isSearching {
  ///     ContentUnavailableView.search(text: searchText)
  ///   } else {
  ///     ContentUnavailableView("No Documents", systemImage: "doc")
  ///   }
  /// }
  /// ```
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter content: Builds the content to show while the outline is empty.
  public func outlineEmptyContent<EmptyContent: View>(
    @ViewBuilder _ content: @escaping () -> EmptyContent
  ) -> Self {
    var copy = self
    copy.behavior.emptyContent = { AnyView(content()) }
    return copy
  }
}

/// Shows the host's empty content over an outline without rows, letting events through to it.
struct OutlineEmptyContent: ViewModifier {
  let isEmpty: Bool
  let content: (() -> AnyView)?

  func body(content outline: Content) -> some View {
    outline.overlay {
      if isEmpty, let content {
        content()
          .allowsHitTesting(false)
      }
    }
  }
}
