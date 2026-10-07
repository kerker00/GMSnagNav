#if os(macOS)
  import AppKit

  /// The outline view used by GMSnagNav, with hooks the delegate API does not offer.
  final class SnagOutlineView: NSOutlineView {
    /// Called for Return and Enter; returns whether the key press was handled.
    var onReturn: (() -> Bool)?
    /// Opens the selection without starting renaming, as in the Finder.
    var onPrimaryAction: (() -> Bool)?

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
      // AppKit routes Command shortcuts through key equivalents before keyDown. Other controls,
      // including the inline rename field, keep their shortcuts while they own the focus.
      if ownsKeyboardFocus, isPrimaryAction(event), onPrimaryAction?() == true {
        return true
      }
      return super.performKeyEquivalent(with: event)
    }

    override func keyDown(with event: NSEvent) {
      // A hosted text field can forward an unhandled event along the responder chain.
      // Do not interpret that event as an outline command while the field owns the focus.
      guard window == nil || ownsKeyboardFocus else {
        super.keyDown(with: event)
        return
      }
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        .subtracting([.numericPad, .function, .capsLock])
      if isPrimaryAction(event), onPrimaryAction?() == true {
        return
      }
      let isReturn = event.keyCode == 36 || event.keyCode == 76
      if isReturn, modifiers.isEmpty, onReturn?() == true { return }
      super.keyDown(with: event)
    }

    /// Transfers focus for a row click without taking it from an embedded editor or control.
    func takeKeyboardFocusForRowClick(at location: NSPoint?) {
      if let location {
        var hit = hitTest(convert(location, to: superview))
        while let view = hit, view !== self {
          if view is NSText || view is NSControl { return }
          hit = view.superview
        }
      }
      window?.makeFirstResponder(self)
    }

    var ownsKeyboardFocus: Bool {
      guard let responder = window?.firstResponder else { return false }
      if responder === self { return true }
      // SwiftUI row content may own the focus instead of the enclosing outline. It still
      // represents the row, but text editors and interactive controls keep their shortcuts.
      guard let view = responder as? NSView, view.isDescendant(of: self),
        !(view is NSText), !(view is NSControl)
      else { return false }
      return true
    }

    private func isPrimaryAction(_ event: NSEvent) -> Bool {
      let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        .subtracting([.numericPad, .function, .capsLock])
      return modifiers == .command
        && (event.keyCode == 125 || event.charactersIgnoringModifiers?.lowercased() == "o")
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
