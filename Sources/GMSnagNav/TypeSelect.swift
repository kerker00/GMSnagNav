import SwiftUI

extension SnagOutline {
  /// Lets the user select a row by typing the start of its text, as in the Finder.
  ///
  /// While the outline has keyboard focus on macOS, typing letters selects the next visible row
  /// whose text starts with them. Collapsed children are not searched, and rows that cannot be
  /// selected are skipped. iOS and iPadOS offer no type select in lists, so the closure is not
  /// called there.
  ///
  /// Like the Finder, type select does not open collapsed containers. To find elements anywhere
  /// in the tree, offer a search that filters the outline.
  ///
  /// The outline cannot read the text of your SwiftUI rows, so return the text the user sees:
  ///
  /// ```swift
  /// .outlineTypeSelect { item in item.name }
  /// ```
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter text: Returns the text to match for an element, or `nil` to skip its row.
  public func outlineTypeSelect(_ text: @escaping (Element) -> String?) -> Self {
    var copy = self
    copy.behavior.typeSelectText = text
    return copy
  }
}
