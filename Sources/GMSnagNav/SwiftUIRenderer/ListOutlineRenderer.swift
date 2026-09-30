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
  let rowContent: (Element) -> RowContent

  var body: some View {
    let rows = tree.visibleRows(expanded: expansion)
    switch selection {
    case .none:
      List { rowsView(rows) }
    case .single(let binding):
      List(selection: binding) { rowsView(rows) }
    case .multiple(let binding):
      List(selection: binding) { rowsView(rows) }
    }
  }

  private func rowsView(_ rows: [VisibleRow<ID>]) -> some View {
    ForEach(rows, id: \.id) { row in
      if let element = tree.element(row.id) {
        OutlineRowView(
          row: row,
          isExpanded: row.isExpanded,
          toggle: { toggle(row.id) },
          content: rowContent(element))
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

/// One row: indentation, disclosure chevron and the host's content.
struct OutlineRowView<ID: Hashable, Content: View>: View {
  /// The horizontal distance between two nesting levels.
  static var indentation: CGFloat { 14 }

  let row: VisibleRow<ID>
  let isExpanded: Bool
  let toggle: () -> Void
  let content: Content

  var body: some View {
    HStack(spacing: 4) {
      disclosure
      content
    }
    .padding(.leading, CGFloat(row.depth) * Self.indentation)
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
