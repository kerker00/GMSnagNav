import SwiftUI

extension View {
  /// Navigates a collapsed `NavigationSplitView` — such as on iPhone — from an outline's
  /// selection, like a SwiftUI `List` does on its own.
  ///
  /// A collapsed split view shows its detail column by itself only for selections made in a
  /// `List`. Apply this modifier to the `NavigationSplitView` and pass it the binding of its
  /// `preferredCompactColumn`:
  ///
  /// ```swift
  /// NavigationSplitView(preferredCompactColumn: $column) {
  ///   SnagOutline(items, children: \.children, selection: $selection) { Text($0.name) }
  /// } detail: {
  ///   DetailView(selection)
  /// }
  /// .outlineCompactNavigation(selection: $selection, column: $column)
  /// ```
  ///
  /// Selecting an element then shows the detail column, and navigating back to the sidebar in a
  /// compact size class clears the selection, so the same row can be opened again — like Mail on
  /// iPhone. In a regular size class, where sidebar and detail are side by side, nothing changes.
  ///
  /// - Parameters:
  ///   - selection: The selection bound to the outline.
  ///   - column: The binding passed to the split view's `preferredCompactColumn`.
  public func outlineCompactNavigation<ID: Hashable>(
    selection: Binding<ID?>, column: Binding<NavigationSplitViewColumn>
  ) -> some View {
    modifier(CompactOutlineNavigation(selection: selection, column: column))
  }
}

/// Keeps a collapsed split view's visible column in step with an outline's selection.
private struct CompactOutlineNavigation<ID: Hashable>: ViewModifier {
  @Binding var selection: ID?
  @Binding var column: NavigationSplitViewColumn

  #if os(iOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
  #endif

  func body(content: Content) -> some View {
    content
      .onChange(of: selection) {
        if isCompact, selection != nil { column = .detail }
      }
      .onChange(of: column) {
        if column == .sidebar, isCompact { selection = nil }
      }
  }

  private var isCompact: Bool {
    #if os(iOS)
      horizontalSizeClass == .compact
    #else
      false
    #endif
  }
}
