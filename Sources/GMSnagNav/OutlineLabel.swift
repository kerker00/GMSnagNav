import SwiftUI

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
/// A title that does not fit ends in an ellipsis, and resting the pointer on it shows the whole
/// title in a tooltip, like the rows of native sidebars on macOS. A title that fits shows no
/// tooltip. On iPhone, which has no pointer, it behaves like a plain `Label`.
///
/// While its row is being renamed — see `outlineRenaming(_:canRename:onRename:)` — the title
/// turns into a text field.
public struct OutlineLabel: View {
  private let title: String
  private let systemImage: String

  /// Creates a label with a title and the name of an SF Symbol.
  public init(_ title: String, systemImage: String) {
    self.title = title
    self.systemImage = systemImage
  }

  @Environment(\.outlineRenameSession) private var renameSession
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize

  /// The content of the label.
  public var body: some View {
    #if os(iOS)
      // There is one title on iOS. Keep its native text metadata for Dynamic Type auditing;
      // the decorative icon is hidden and the containing row combines the accessible title.
      label
    #else
      if renameSession != nil {
        label
      } else {
        label
          .accessibilityElement(children: .ignore)
          .accessibilityLabel(title)
          // Without a trait, the combined element has no role on macOS 27.
          .accessibilityAddTraits(.isStaticText)
      }
    #endif
  }

  private var label: some View {
    Label {
      if renameSession != nil {
        OutlineRenamableText(title)
      } else {
        fittingTitle
      }
    } icon: {
      Image(systemName: systemImage)
        .accessibilityHidden(true)
    }
  }

  @ViewBuilder private var fittingTitle: some View {
    #if os(iOS)
      // UIKit supplies the row's width. A single Text avoids exposing the hidden, fixed-width
      // alternative of ViewThatFits to accessibility clipping checks.
      Text(title)
        .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
        .fixedSize(horizontal: false, vertical: true)
    #else
      // Pure SwiftUI on purpose: an AppKit text field in a row breaks the row's context menu.
      if dynamicTypeSize.isAccessibilitySize {
        Text(title)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        ViewThatFits(in: .horizontal) {
          Text(title)
            .fixedSize()
          Text(title)
            .lineLimit(1)
            .truncationMode(.tail)
            .help(title)
        }
      }
    #endif
  }
}
