import SwiftUI

extension SnagOutline {
  /// Shows top-level elements as section headers, like "Favorites" and "Locations" in the
  /// Finder's sidebar.
  ///
  /// Return a title for each root element that heads a section, and `nil` for all others. The
  /// outline draws section headers itself, in the platform's sidebar header style, instead of
  /// your row content: a group row on macOS, and a bold heading on iOS and iPadOS. The children
  /// of a section are its entries, shown without extra indentation.
  ///
  /// Section headers are never selected. Clicking or tapping a header shows or hides its
  /// entries, through the same expansion binding as any other element; on macOS the header also
  /// offers the system's show and hide button while the pointer rests on it. Headers can be
  /// dragged when ``outlineDraggable(_:)`` allows it, for example to reorder sections, and drops
  /// onto or into a section reach your drop validation like any other.
  ///
  /// ```swift
  /// .outlineSections { item in item.isSection ? item.name : nil }
  /// ```
  ///
  /// Only root elements become section headers; the closure is not called for nested elements.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter title: Returns the header title for a root element, or `nil` for a regular row.
  public func outlineSections(_ title: @escaping (Element) -> String?) -> Self {
    var copy = self
    copy.behavior.sectionTitle = title
    return copy
  }
}

extension OutlineBehavior {
  /// The header title of a root element that heads a section, or `nil` for every other element.
  func sectionTitle(of id: Element.ID, in tree: OutlineTree<Element>) -> String? {
    guard let sectionTitle, let node = tree.node(id), node.parent == nil else { return nil }
    return sectionTitle(node.element)
  }

  /// Whether the element can be selected: allowed by the host and not a section header.
  func canSelect(_ id: Element.ID, in tree: OutlineTree<Element>) -> Bool {
    guard let element = tree.element(id) else { return false }
    return canSelect(element) && sectionTitle(of: id, in: tree) == nil
  }

  /// The nesting level used for indentation: entries of a section are not indented below their
  /// header.
  func indentationDepth(of id: Element.ID, in tree: OutlineTree<Element>) -> Int {
    guard let node = tree.node(id) else { return 0 }
    guard let root = tree.ancestors(of: id).last, sectionTitle(of: root, in: tree) != nil
    else { return node.depth }
    return node.depth - 1
  }
}

/// A section header in the platform's sidebar style.
struct OutlineSectionHeader: View {
  let title: String

  var body: some View {
    Text(title)
      #if os(macOS)
        .font(.system(size: 11, weight: .semibold))
        .foregroundStyle(.secondary)
      #else
        .font(.headline)
        .foregroundStyle(.primary)
      #endif
      .lineLimit(1)
      .accessibilityAddTraits(.isHeader)
  }
}
