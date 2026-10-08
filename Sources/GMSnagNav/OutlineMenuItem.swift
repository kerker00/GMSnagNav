import SwiftUI

/// An entry of an outline's context menu: an action, a submenu, or a divider.
///
/// Menus built from items render natively on every platform — as a SwiftUI menu on macOS and as a
/// `UIMenu` on iOS. On iOS this lets UIKit share one long press between the menu and dragging, like
/// the Files app: moving the finger drags the row, holding it still opens the menu.
///
/// ```swift
/// .outlineContextMenuItems { ids in
///   [
///     .action("Rename", systemImage: "pencil") { rename(ids) },
///     .menu("Move to", systemImage: "folder", children: folders.map { folder in
///       .action(folder.name) { move(ids, into: folder) }
///     }),
///     .divider,
///     .action("Delete", systemImage: "trash", role: .destructive) { delete(ids) },
///   ]
/// }
/// ```
public struct OutlineMenuItem {
  enum Kind {
    case action(@MainActor () -> Void)
    case menu([OutlineMenuItem])
    case divider
  }

  let kind: Kind
  let title: String
  let systemImage: String?
  let isDestructive: Bool
  let isDisabled: Bool

  /// An action the user can choose.
  ///
  /// - Parameters:
  ///   - title: The title shown in the menu.
  ///   - systemImage: The name of an SF Symbol shown next to the title.
  ///   - role: `.destructive` shows the action in red; other roles are shown as usual.
  ///   - isDisabled: Whether the action is shown but cannot be chosen.
  ///   - perform: Runs when the user chooses the action.
  public static func action(
    _ title: String, systemImage: String? = nil, role: ButtonRole? = nil,
    isDisabled: Bool = false, perform: @escaping @MainActor () -> Void
  ) -> Self {
    Self(
      kind: .action(perform), title: title, systemImage: systemImage,
      isDestructive: role == .destructive, isDisabled: isDisabled)
  }

  /// A submenu with its own items.
  ///
  /// - Parameters:
  ///   - title: The title of the submenu.
  ///   - systemImage: The name of an SF Symbol shown next to the title.
  ///   - children: The items of the submenu.
  public static func menu(
    _ title: String, systemImage: String? = nil, children: [OutlineMenuItem]
  ) -> Self {
    Self(
      kind: .menu(children), title: title, systemImage: systemImage, isDestructive: false,
      isDisabled: false)
  }

  /// A separator between groups of items.
  public static var divider: Self {
    Self(kind: .divider, title: "", systemImage: nil, isDestructive: false, isDisabled: false)
  }
}

extension SnagOutline {
  /// Adds a native context menu, built from items, for the elements the user right-clicks or
  /// long-presses.
  ///
  /// The menu receives the identifiers it applies to, like
  /// ``outlineContextMenu(_:)``: the whole selection when the pressed row is selected, otherwise
  /// the pressed element alone, and an empty set on empty space in an outline with selection.
  /// Return no items to show no menu.
  ///
  /// Prefer this modifier over ``outlineContextMenu(_:)`` where its items suffice. On macOS the
  /// menu is an `NSMenu` that opens anywhere in a row and outlines the row it applies to, like in
  /// the Finder. On iOS its menu and dragging share one long press, like in the Files app.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter items: Builds the menu items for a set of identifiers.
  public func outlineContextMenuItems(
    _ items: @escaping @MainActor (Set<ID>) -> [OutlineMenuItem]
  ) -> Self {
    var copy = self
    copy.behavior.contextMenuItems = items
    // Renderers without a native menu of their own show the items as a SwiftUI menu.
    copy.behavior.contextMenu = { ids in AnyView(OutlineMenuItemsView(items: items(ids))) }
    return copy
  }
}

/// Shows menu items as SwiftUI menu content: buttons, submenus and dividers.
struct OutlineMenuItemsView: View {
  let items: [OutlineMenuItem]

  var body: some View {
    ForEach(items.indices, id: \.self) { index in
      let item = items[index]
      switch item.kind {
      case .action(let perform):
        Button(role: item.isDestructive ? .destructive : nil, action: perform) {
          label(for: item)
        }
        .disabled(item.isDisabled)
      case .menu(let children):
        Menu {
          OutlineMenuItemsView(items: children)
        } label: {
          label(for: item)
        }
      case .divider:
        Divider()
      }
    }
  }

  @ViewBuilder private func label(for item: OutlineMenuItem) -> some View {
    if let systemImage = item.systemImage {
      Label(item.title, systemImage: systemImage)
    } else {
      Text(item.title)
    }
  }
}
