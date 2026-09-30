import SwiftUI

#if os(macOS)
  import AppKit
#endif

/// The visual style of a ``SnagOutline``.
public enum SnagOutlineStyle: Hashable, Sendable {
  /// The platform's default: a source list on macOS, and the list style SwiftUI picks for the
  /// context on iOS — a sidebar in a split view's sidebar column.
  case automatic
  /// A sidebar: a translucent source list on macOS, SwiftUI's sidebar list style on iOS.
  case sidebar
  /// A plain list without sidebar styling, for outlines inside regular content.
  case plain
}

/// Visual options configured through `SnagOutline`'s modifiers.
struct OutlineAppearance {
  /// The default horizontal distance between two nesting levels: AppKit's source-list spacing on
  /// macOS, and a wider step on iOS, whose taller list rows need more indentation to read clearly.
  static var defaultIndentation: CGFloat {
    #if os(macOS)
      14
    #else
      24
    #endif
  }

  var style = SnagOutlineStyle.automatic
  var indentation = defaultIndentation
  #if os(macOS)
    var appKitConfiguration: (@MainActor (NSOutlineView) -> Void)?
  #endif
}

extension SnagOutline {
  /// Sets the visual style of the outline.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter style: The style to use. The default is ``SnagOutlineStyle/automatic``.
  public func outlineStyle(_ style: SnagOutlineStyle) -> Self {
    var copy = self
    copy.appearance.style = style
    return copy
  }

  /// Sets the horizontal distance between two nesting levels.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter width: The indentation per level, in points. Negative values are treated as `0`.
  ///   The default is 14 points on macOS and 24 points on iOS.
  public func outlineIndentation(_ width: CGFloat) -> Self {
    var copy = self
    copy.appearance.indentation = max(width, 0)
    return copy
  }

  #if os(macOS)
    /// Customizes the underlying `NSOutlineView` beyond what GMSnagNav's modifiers offer.
    ///
    /// The closure runs after every update, once GMSnagNav has applied its own configuration, so
    /// changes take effect immediately and override GMSnagNav's settings. Keep it idempotent, and
    /// do not replace the outline view's data source, delegate, target or actions — GMSnagNav
    /// relies on them.
    ///
    /// ```swift
    /// SnagOutline(items, children: \.children, selection: $selection) { Text($0.name) }
    ///   .outlineAppKitConfiguration { outlineView in
    ///     outlineView.rowSizeStyle = .large
    ///   }
    /// ```
    ///
    /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
    ///
    /// - Parameter configure: Receives the outline view to customize.
    public func outlineAppKitConfiguration(
      _ configure: @escaping @MainActor (NSOutlineView) -> Void
    ) -> Self {
      var copy = self
      copy.appearance.appKitConfiguration = configure
      return copy
    }
  #endif
}
