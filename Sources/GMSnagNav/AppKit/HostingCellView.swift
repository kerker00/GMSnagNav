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

    /// Shows new row content.
    func show(_ content: AnyView) {
      self.content = content
      render()
    }

    private func render() {
      hostingView.rootView = AnyView(
        content
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
          .environment(
            \.backgroundProminence, backgroundStyle == .emphasized ? .increased : .standard))
    }
  }
#endif
