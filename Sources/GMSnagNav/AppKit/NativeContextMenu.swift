#if os(macOS)
  import AppKit

  /// Runs a menu item's action; AppKit's target-action needs an Objective-C target.
  @MainActor
  final class OutlineMenuActionTarget: NSObject {
    private let perform: @MainActor () -> Void

    init(_ perform: @escaping @MainActor () -> Void) {
      self.perform = perform
    }

    @objc func performAction(_ sender: Any?) {
      perform()
    }
  }

  extension OutlineMenuItem {
    /// Converts menu items to AppKit menu items, with submenus and separators.
    ///
    /// Each action item keeps its target as `representedObject`, since `target` is weak.
    @MainActor static func nativeItems(for items: [OutlineMenuItem]) -> [NSMenuItem] {
      items.map { item in
        switch item.kind {
        case .divider:
          return .separator()
        case .action(let perform):
          let target = OutlineMenuActionTarget(perform)
          let menuItem = NSMenuItem(
            title: item.title, action: #selector(OutlineMenuActionTarget.performAction(_:)),
            keyEquivalent: "")
          menuItem.target = target
          menuItem.representedObject = target
          menuItem.isEnabled = !item.isDisabled
          menuItem.image = item.nativeImage
          return menuItem
        case .menu(let children):
          let menuItem = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
          let submenu = NSMenu(title: item.title)
          submenu.autoenablesItems = false
          submenu.items = nativeItems(for: children)
          menuItem.submenu = submenu
          menuItem.image = item.nativeImage
          return menuItem
        }
      }
    }

    private var nativeImage: NSImage? {
      systemImage.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
    }
  }
#endif
