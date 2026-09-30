#if os(macOS)
  import AppKit
  import SwiftUI

  /// A table cell that shows the host's SwiftUI row content.
  ///
  /// AppKit tells cells about the selection through `backgroundStyle`: `.emphasized` while the
  /// row is selected in a focused outline. The cell forwards that as SwiftUI's
  /// `backgroundProminence`, so hierarchical styles such as `.primary` and `.secondary` switch to
  /// their high-contrast variants on the accent-colored selection — just like rows of a native
  /// SwiftUI `List`.
  ///
  /// AppKit also tells cells the row size — small, medium or large, following the sidebar icon
  /// size in System Settings for source lists. Native cells then use 11, 13 or 15 point text and
  /// symbols; the cell passes the same size to the SwiftUI content as its default font.
  final class HostingCellView: NSTableCellView {
    static let reuseIdentifier = NSUserInterfaceItemIdentifier("GMSnagNav.HostingCell")

    private let hostingView = NSHostingView(rootView: AnyView(EmptyView()))
    private var content = AnyView(EmptyView())

    init() {
      super.init(frame: .zero)
      identifier = Self.reuseIdentifier

      hostingView.translatesAutoresizingMaskIntoConstraints = false
      // Let the outline decide the row height; the hosted content is centered in it.
      hostingView.sizingOptions = []
      addSubview(hostingView)
      NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
        hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
        hostingView.topAnchor.constraint(equalTo: topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      nil
    }

    override var backgroundStyle: NSView.BackgroundStyle {
      didSet {
        if backgroundStyle != oldValue { render() }
      }
    }

    override var rowSizeStyle: NSTableView.RowSizeStyle {
      didSet {
        if rowSizeStyle != oldValue { render() }
      }
    }

    /// The point size of native text in rows of the current size, or `nil` for custom sizes.
    var fontSize: CGFloat? {
      switch rowSizeStyle {
      case .small: 11
      case .medium: 13
      case .large: 15
      default: nil
      }
    }

    /// Shows new row content.
    func show(_ content: AnyView) {
      self.content = content
      render()
    }

    private func render() {
      hostingView.rootView = AnyView(
        content
          .font(fontSize.map { .system(size: $0) })
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .environment(
            \.backgroundProminence, backgroundStyle == .emphasized ? .increased : .standard))
    }
  }
#endif
