#if os(macOS)
  import AppKit

  /// The outline view used by GMSnagNav, with hooks the delegate API does not offer.
  final class SnagOutlineView: NSOutlineView {
    /// Called for Return and Enter; returns whether the key press was handled.
    var onReturn: (() -> Bool)?

    override func keyDown(with event: NSEvent) {
      let isReturn = event.keyCode == 36 || event.keyCode == 76
      if isReturn, onReturn?() == true { return }
      super.keyDown(with: event)
    }
  }

  /// Receives the outline's click actions and forwards them to closures.
  ///
  /// Target-action needs Objective-C selectors, which generic types cannot provide, so the
  /// generic coordinator routes its clicks through this small object.
  @MainActor
  final class OutlineClickTarget: NSObject {
    var onClick: (() -> Void)?
    var onDoubleClick: (() -> Void)?

    @objc func click(_ sender: Any?) {
      onClick?()
    }

    @objc func doubleClick(_ sender: Any?) {
      onDoubleClick?()
    }
  }
#endif
