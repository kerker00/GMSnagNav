import SwiftUI

/// Renders an outline as a flat SwiftUI `List` of the visible rows.
///
/// Flattening the tree into one `ForEach` — instead of nesting `DisclosureGroup`s — keeps every
/// row a direct child of the list. That is what later lets `onMove` reorder rows across levels.
struct ListOutlineRenderer<Element: Identifiable, RowContent: View>: View
where Element.ID: Sendable {
  typealias ID = Element.ID

  let tree: OutlineTree<Element>
  let selection: OutlineSelection<ID>
  @Binding var expansion: Set<ID>
  let behavior: OutlineBehavior<Element>
  let appearance: OutlineAppearance
  let rowContent: (Element) -> RowContent

  var body: some View {
    list(tree.visibleRows(expanded: expansion))
      .modifier(ListStyleModifier(style: appearance.style))
  }

  @ViewBuilder private func list(_ rows: [VisibleRow<ID>]) -> some View {
    switch selection {
    case .none:
      List { rowsView(rows, hasSelection: false) }
    case .single(let binding):
      List(selection: binding) { rowsView(rows, hasSelection: true) }
        .modifier(SelectionActions(behavior: behavior))
    case .multiple(let binding):
      List(selection: binding) { rowsView(rows, hasSelection: true) }
        .modifier(SelectionActions(behavior: behavior))
    }
  }

  /// - Parameter hasSelection: Whether the list binds a selection. Lists with selection route the
  ///   primary action and the context menu through `contextMenu(forSelectionType:)`; lists without
  ///   one, and rows that cannot be selected, attach them to each row instead.
  private func rowsView(_ rows: [VisibleRow<ID>], hasSelection: Bool) -> some View {
    ForEach(rows, id: \.id) { row in
      if let element = tree.element(row.id) {
        let isSelectable = behavior.canSelect(element)
        OutlineRowView(
          row: row,
          indentation: appearance.indentation,
          isExpanded: row.isExpanded,
          toggle: { toggle(row.id) },
          content: rowContent(element)
        )
        .selectionDisabled(!isSelectable)
        .modifier(
          RowTapBehavior(
            togglesExpansion: !isSelectable && row.isExpandable && row.childCount > 0,
            primaryAction: hasSelection
              ? nil : behavior.primaryAction.map { action in { action([row.id]) } },
            toggle: { toggle(row.id) })
        )
        .modifier(
          RowContextMenu(
            menu: hasSelection && isSelectable
              ? nil : behavior.contextMenu.map { menu in { menu([row.id]) } }))
      }
    }
  }

  private func toggle(_ id: ID) {
    withAnimation(.snappy(duration: 0.2)) {
      if expansion.contains(id) {
        expansion.remove(id)
      } else {
        expansion.insert(id)
      }
    }
  }
}

/// Maps ``SnagOutlineStyle`` to SwiftUI list styles.
private struct ListStyleModifier: ViewModifier {
  let style: SnagOutlineStyle

  func body(content: Content) -> some View {
    switch style {
    case .automatic: content
    case .sidebar: content.listStyle(.sidebar)
    case .plain: content.listStyle(.plain)
    }
  }
}

/// Routes the primary action and context menu of lists with selection through SwiftUI's
/// selection-aware API, so a multi-selection is handled as a whole.
private struct SelectionActions<Element: Identifiable>: ViewModifier {
  let behavior: OutlineBehavior<Element>

  func body(content: Content) -> some View {
    if behavior.primaryAction == nil && behavior.contextMenu == nil {
      content
    } else {
      content.contextMenu(
        forSelectionType: Element.ID.self,
        menu: { ids in behavior.contextMenu?(ids) },
        primaryAction: { ids in
          if !ids.isEmpty { behavior.primaryAction?(ids) }
        })
    }
  }
}

/// Attaches a context menu to a single row, for lists without selection and unselectable rows.
private struct RowContextMenu: ViewModifier {
  let menu: (() -> AnyView)?

  func body(content: Content) -> some View {
    if let menu {
      content.contextMenu { menu() }
    } else {
      content
    }
  }
}

/// Handles taps on a row that are not selection: toggling non-selectable containers and, in lists
/// without selection, the primary action.
private struct RowTapBehavior: ViewModifier {
  let togglesExpansion: Bool
  let primaryAction: (() -> Void)?
  let toggle: () -> Void

  func body(content: Content) -> some View {
    if let primaryAction {
      content
        .contentShape(.rect)
        .onTapGesture(count: Self.activationTapCount, perform: primaryAction)
    } else if togglesExpansion {
      content
        .contentShape(.rect)
        .onTapGesture(perform: toggle)
    } else {
      content
    }
  }

  /// Double-click activates on macOS, like in Finder; a single tap activates on iOS.
  private static var activationTapCount: Int {
    #if os(macOS)
      2
    #else
      1
    #endif
  }
}

/// One row: indentation, disclosure chevron and the host's content.
struct OutlineRowView<ID: Hashable, Content: View>: View {
  let row: VisibleRow<ID>
  /// The horizontal distance between two nesting levels.
  let indentation: CGFloat
  let isExpanded: Bool
  let toggle: () -> Void
  let content: Content

  var body: some View {
    HStack(spacing: 4) {
      disclosure
      content
    }
    .padding(.leading, CGFloat(row.depth) * indentation)
    .accessibilityElement(children: .combine)
    .modifier(ExpansionAccessibility(row: row, toggle: toggle))
  }

  @ViewBuilder private var disclosure: some View {
    if row.isExpandable && row.childCount > 0 {
      Button(action: toggle) {
        Image(systemName: "chevron.right")
          .font(.caption.weight(.semibold))
          .foregroundStyle(.secondary)
          .rotationEffect(.degrees(isExpanded ? 90 : 0))
          .frame(width: 16, height: 16)
          .contentShape(.rect)
      }
      .buttonStyle(.plain)
      .accessibilityHidden(true)
    } else {
      Color.clear.frame(width: 16, height: 16)
    }
  }
}

/// Exposes expanding and collapsing to assistive technologies.
private struct ExpansionAccessibility<ID: Hashable>: ViewModifier {
  let row: VisibleRow<ID>
  let toggle: () -> Void

  func body(content: Content) -> some View {
    if row.isExpandable && row.childCount > 0 {
      content
        .accessibilityValue(row.isExpanded ? Text("Expanded") : Text("Collapsed"))
        .accessibilityAction(named: row.isExpanded ? Text("Collapse") : Text("Expand"), toggle)
    } else {
      content
    }
  }
}
