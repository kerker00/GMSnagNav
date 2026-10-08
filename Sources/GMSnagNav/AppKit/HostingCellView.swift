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

    let hostingView = RowHostingView(rootView: AnyView(EmptyView()))
    private var content = AnyView(EmptyView())
    private lazy var trailingConstraint = hostingView.trailingAnchor.constraint(
      equalTo: trailingAnchor)

    /// The space kept free at the trailing edge, such as in plain outlines whose cells reach the
    /// edge of the row.
    var trailingInset: CGFloat = 0 {
      didSet { if trailingInset != oldValue { needsLayout = true } }
    }

    /// Whether the cell heads a section in a source list. AppKit shows a show/hide button at its
    /// trailing edge while the pointer rests on it and shrinks the cell to make room; the content
    /// keeps that room at all times, so accessories such as badges stay in place.
    var reservesShowHideButton = false {
      didSet { if reservesShowHideButton != oldValue { needsLayout = true } }
    }

    /// The room for the show/hide button, measured from the trailing edge of the row.
    static var showHideButtonReserve: CGFloat { 26 }

    init() {
      super.init(frame: .zero)
      identifier = Self.reuseIdentifier

      hostingView.translatesAutoresizingMaskIntoConstraints = false
      // Let the outline decide the row height; the hosted content is centered in it.
      hostingView.sizingOptions = []
      addSubview(hostingView)
      NSLayoutConstraint.activate([
        hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
        trailingConstraint,
        hostingView.topAnchor.constraint(equalTo: topAnchor),
        hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
      ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
      nil
    }

    override func layout() {
      var inset = trailingInset
      if reservesShowHideButton, let row = superview {
        let limit =
          convert(NSPoint(x: row.bounds.maxX, y: 0), from: row).x
          - Self.showHideButtonReserve
        inset = max(inset, bounds.maxX - limit)
      }
      if trailingConstraint.constant != -inset { trailingConstraint.constant = -inset }
      super.layout()
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
          .environment(\.outlineRowTextSize, fontSize)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .environment(
            \.backgroundProminence, backgroundStyle == .emphasized ? .increased : .standard))
    }
  }

  /// Hosts a row's SwiftUI content as part of its cell. As an accessibility element of its own,
  /// the hosting view adds an unnamed group between the cell and the content.
  final class RowHostingView: NSHostingView<AnyView> {
    override func isAccessibilityElement() -> Bool { false }
  }
#endif
