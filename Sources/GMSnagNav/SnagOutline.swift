import SwiftUI

/// A nested outline of the host's own data, with selection and expansion.
///
/// Pass the root elements and how to read an element's children — the same shape as SwiftUI's
/// `List(_:children:)` and `OutlineGroup`:
///
/// ```swift
/// SnagOutline(library.roots, children: \.children, selection: $selection, expansion: $expanded) {
///   item in
///   Label(item.name, systemImage: item.systemImage)
/// }
/// ```
///
/// Children are read as an optional array: `nil` marks a leaf that can never have children, while
/// an empty array marks a container that is currently empty, such as an empty folder. An empty
/// container shows no disclosure indicator, since there is nothing to reveal, but accepts drops
/// onto its row.
///
/// Identifiers must be unique across the whole tree, not only among siblings. A repeated
/// identifier shows only its first occurrence; see `onOutlineDuplicateIDs(_:)`. The outline keeps
/// no copy of the data between updates; every change to `data` is reflected the next time SwiftUI
/// renders the view.
///
/// ## Compact split views
///
/// A collapsed `NavigationSplitView`, such as on iPhone, navigates to its detail column by itself
/// only for selections in a SwiftUI `List`. Apply `outlineCompactNavigation(selection:column:)`
/// to the split view for the same behavior with an outline.
public struct SnagOutline<Data: RandomAccessCollection, RowContent: View>: View
where Data.Element: Identifiable, Data.Element.ID: Sendable {
  /// The type of the elements shown in the outline.
  public typealias Element = Data.Element
  /// The type identifying elements, used for selection and expansion.
  public typealias ID = Element.ID

  let data: Data
  let children: (Element) -> [Element]?
  let selection: OutlineSelection<ID>
  let expansion: Binding<Set<ID>>?
  let rowContent: (Element) -> RowContent
  var behavior = OutlineBehavior<Element>()
  var appearance = OutlineAppearance()

  @State private var internalExpansion: Set<ID> = []
  @Environment(\.springLoadingBehavior) private var springLoadingBehavior

  /// Creates an outline with single selection.
  ///
  /// - Parameters:
  ///   - data: The root elements.
  ///   - children: Returns the children of an element, or `nil` for a leaf. Pass a key path such
  ///     as `\.children` or a closure.
  ///   - selection: The identifier of the selected element, or `nil` if nothing is selected.
  ///   - expansion: The identifiers of the expanded elements. When omitted, the outline keeps its
  ///     expansion state internally and starts fully collapsed.
  ///   - rowContent: Builds the content of the row for an element.
  public init(
    _ data: Data,
    children: @escaping (Element) -> [Element]?,
    selection: Binding<ID?>,
    expansion: Binding<Set<ID>>? = nil,
    @ViewBuilder rowContent: @escaping (Element) -> RowContent
  ) {
    self.init(
      data, children: children, selection: .single(selection), expansion: expansion,
      rowContent: rowContent)
  }

  /// Creates an outline that allows selecting several elements at once.
  ///
  /// - Parameters:
  ///   - data: The root elements.
  ///   - children: Returns the children of an element, or `nil` for a leaf. Pass a key path such
  ///     as `\.children` or a closure.
  ///   - selection: The identifiers of the selected elements.
  ///   - expansion: The identifiers of the expanded elements. When omitted, the outline keeps its
  ///     expansion state internally and starts fully collapsed.
  ///   - rowContent: Builds the content of the row for an element.
  public init(
    _ data: Data,
    children: @escaping (Element) -> [Element]?,
    selection: Binding<Set<ID>>,
    expansion: Binding<Set<ID>>? = nil,
    @ViewBuilder rowContent: @escaping (Element) -> RowContent
  ) {
    self.init(
      data, children: children, selection: .multiple(selection), expansion: expansion,
      rowContent: rowContent)
  }

  /// Creates an outline without selection.
  ///
  /// - Parameters:
  ///   - data: The root elements.
  ///   - children: Returns the children of an element, or `nil` for a leaf. Pass a key path such
  ///     as `\.children` or a closure.
  ///   - expansion: The identifiers of the expanded elements. When omitted, the outline keeps its
  ///     expansion state internally and starts fully collapsed.
  ///   - rowContent: Builds the content of the row for an element.
  public init(
    _ data: Data,
    children: @escaping (Element) -> [Element]?,
    expansion: Binding<Set<ID>>? = nil,
    @ViewBuilder rowContent: @escaping (Element) -> RowContent
  ) {
    self.init(
      data, children: children, selection: .none, expansion: expansion, rowContent: rowContent)
  }

  private init(
    _ data: Data,
    children: @escaping (Element) -> [Element]?,
    selection: OutlineSelection<ID>,
    expansion: Binding<Set<ID>>?,
    rowContent: @escaping (Element) -> RowContent
  ) {
    self.data = data
    self.children = children
    self.selection = selection
    self.expansion = expansion
    self.rowContent = rowContent
  }

  /// The content and behavior of the view.
  public var body: some View {
    #if os(macOS)
      AppKitOutlineRenderer(
        tree: OutlineTree(data, children: children),
        selection: selection,
        expansion: expansion ?? $internalExpansion,
        behavior: behavior,
        appearance: appearance,
        springLoading: springLoadingBehavior,
        rowContent: rowContent
      )
      .modifier(EmptySpaceContextMenu(selection: selection, behavior: behavior))
    #else
      UIKitOutlineRenderer(
        tree: OutlineTree(data, children: children),
        selection: selection,
        expansion: expansion ?? $internalExpansion,
        behavior: behavior,
        appearance: appearance,
        springLoading: springLoadingBehavior,
        rowContent: rowContent)
    #endif
  }
}

// MARK: - Behavior modifiers

extension SnagOutline {
  /// Decides which elements can be selected.
  ///
  /// Rows of elements that are not selectable ignore clicks and taps for selection; clicking a
  /// non-selectable row that has children toggles its expansion instead. Use this for grouping elements,
  /// such as folders in a project list, that have no detail view of their own.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter isSelectable: Returns whether an element can be selected. All elements are
  ///   selectable by default.
  public func outlineSelectable(_ isSelectable: @escaping (Element) -> Bool) -> Self {
    var copy = self
    copy.behavior.isSelectable = isSelectable
    return copy
  }

  /// Performs an action when the user activates elements.
  ///
  /// The action runs on a double-click or Return on macOS and on a tap on iOS. For outlines with selection,
  /// it receives the selected elements when the activated row is part of the selection, otherwise
  /// the activated element alone.
  ///
  /// On iOS, a tap first selects the row, then runs the action.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter action: Receives the identifiers of the activated elements.
  public func outlinePrimaryAction(_ action: @escaping (Set<ID>) -> Void) -> Self {
    var copy = self
    copy.behavior.primaryAction = action
    return copy
  }

  /// Adds a context menu for the elements the user right-clicks or long-presses.
  ///
  /// The menu receives the identifiers it applies to:
  ///
  /// - the whole selection when the user opens the menu on a selected row,
  /// - only the clicked element when the row is not selected or not selectable,
  /// - an empty set when the menu opens on empty space in an outline with selection — useful for
  ///   actions such as "New Folder" at the root level. macOS only: on iOS, empty space shows no
  ///   menu, because a long press there would lift the whole outline.
  ///
  /// Return no content to show no menu for a set of identifiers.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter menu: Builds the menu items for a set of identifiers.
  public func outlineContextMenu<MenuContent: View>(
    @ViewBuilder _ menu: @escaping (Set<ID>) -> MenuContent
  ) -> Self {
    var copy = self
    copy.behavior.contextMenu = { AnyView(menu($0)) }
    return copy
  }
}

/// Optional behavior configured through `SnagOutline`'s modifiers.
struct OutlineBehavior<Element: Identifiable> where Element.ID: Sendable {
  var isSelectable: ((Element) -> Bool)?
  var primaryAction: ((Set<Element.ID>) -> Void)?
  var contextMenu: ((Set<Element.ID>) -> AnyView)?
  /// The items of a native context menu, set by `outlineContextMenuItems(_:)`, which also sets
  /// `contextMenu` for renderers that show the items as SwiftUI content.
  var contextMenuItems: (@MainActor (Set<Element.ID>) -> [OutlineMenuItem])?
  var canDrag: ((Element) -> Bool)?
  var drop: OutlineDropHandler<Element.ID>?
  var duplicateIDs: ((Set<Element.ID>) -> Void)?

  func canSelect(_ element: Element) -> Bool {
    isSelectable?(element) ?? true
  }
}

/// How an outline binds its selection.
enum OutlineSelection<ID: Hashable> {
  case none
  case single(Binding<ID?>)
  case multiple(Binding<Set<ID>>)
}

/// Shows the host's context menu with an empty set of identifiers for space that holds no row.
/// Rows show their own menu from their hosted content.
///
/// macOS only: on iOS a long press on empty space would lift the whole outline as the menu's
/// preview, which can then be dragged around.
struct EmptySpaceContextMenu<Element: Identifiable>: ViewModifier where Element.ID: Sendable {
  let selection: OutlineSelection<Element.ID>
  let behavior: OutlineBehavior<Element>

  func body(content: Content) -> some View {
    if case .none = selection {
      content
    } else if let menu = behavior.contextMenu {
      content.contextMenu { menu([]) }
    } else {
      content
    }
  }
}
