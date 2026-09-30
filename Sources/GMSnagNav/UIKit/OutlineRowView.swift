#if os(iOS)
  import SwiftUI

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
          .accessibilityValue(
            row.isExpanded ? Text("Expanded", bundle: .module) : Text("Collapsed", bundle: .module)
          )
          .accessibilityAction(
            named: row.isExpanded
              ? Text("Collapse", bundle: .module) : Text("Expand", bundle: .module),
            toggle)
      } else {
        content
      }
    }
  }
#endif
