import SwiftUI

#if os(macOS)
  import AppKit
#endif

/// A row title with an icon that shows its whole text in a tooltip when the row is too narrow.
///
/// Use it like `Label` for the rows of a ``SnagOutline``:
///
/// ```swift
/// SnagOutline(items, children: \.children, selection: $selection) { item in
///   OutlineLabel(item.name, systemImage: item.systemImage)
/// }
/// ```
///
/// On macOS, a title that does not fit ends in an ellipsis, and resting the pointer on it shows
/// the whole title in place — like the rows of native sidebars. The title uses the row's text size
/// and turns white on the accent-colored selection. On iOS and iPadOS, where rows have no pointer
/// tooltips, it is a plain `Label`.
public struct OutlineLabel: View {
  private let title: String
  private let systemImage: String

  /// Creates a label with a title and the name of an SF Symbol.
  public init(_ title: String, systemImage: String) {
    self.title = title
    self.systemImage = systemImage
  }

  /// The content of the label.
  public var body: some View {
    #if os(macOS)
      Label {
        ExpandingTitle(title: title)
      } icon: {
        Image(systemName: systemImage)
      }
    #else
      Label(title, systemImage: systemImage)
    #endif
  }
}

#if os(macOS)
  extension EnvironmentValues {
    /// The point size of native text in the current outline row, set by the row's cell.
    @Entry var outlineRowFontSize: CGFloat?
  }

  /// A single-line AppKit label, which offers expansion tooltips for truncated text.
  struct ExpandingTitle: NSViewRepresentable {
    let title: String

    func makeNSView(context: Context) -> NSTextField {
      let field = NSTextField(labelWithString: title)
      field.lineBreakMode = .byTruncatingTail
      field.allowsExpansionToolTips = true
      field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
      return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
      if field.stringValue != title { field.stringValue = title }
      let size = context.environment.outlineRowFontSize ?? NSFont.systemFontSize
      if field.font?.pointSize != size { field.font = .systemFont(ofSize: size) }
      field.textColor =
        context.environment.backgroundProminence == .increased
        ? .alternateSelectedControlTextColor : .labelColor
    }

    /// Takes the width the text needs, or less when the row is narrower, so the text truncates.
    func sizeThatFits(
      _ proposal: ProposedViewSize, nsView field: NSTextField, context: Context
    ) -> CGSize? {
      let fitting = field.intrinsicContentSize
      return CGSize(
        width: min(proposal.width ?? fitting.width, fitting.width), height: fitting.height)
    }
  }
#endif
