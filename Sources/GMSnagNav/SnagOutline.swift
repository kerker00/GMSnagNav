import SwiftUI

/// A nested outline of the host's own data, with selection and expansion.
///
/// Pass the root elements and how to read an element's children — the same shape as SwiftUI's
/// `List(_:children:)` and `OutlineGroup`:
///
/// ```swift
/// SnagOutline(library.roots, children: \.children, selection: $selection, expansion: $expanded) {
///   item in
///   Label(item.name, systemImage: item.systemImage)
/// }
/// ```
///
/// Children are read as an optional array: `nil` marks a leaf that can never have children, while
/// an empty array marks an expandable container that is currently empty, such as an empty folder.
///
/// Identifiers must be unique across the whole tree. The outline keeps no copy of the data between
/// updates; every change to `data` is reflected the next time SwiftUI renders the view.
public struct SnagOutline<Data: RandomAccessCollection, RowContent: View>: View
where Data.Element: Identifiable, Data.Element.ID: Sendable {
  /// The type of the elements shown in the outline.
  public typealias Element = Data.Element
  /// The type identifying elements, used for selection and expansion.
  public typealias ID = Element.ID

  let data: Data
  let children: (Element) -> [Element]?
  let selection: OutlineSelection<ID>
  let expansion: Binding<Set<ID>>?
  let rowContent: (Element) -> RowContent

  @State private var internalExpansion: Set<ID> = []

  /// Creates an outline with single selection.
  ///
  /// - Parameters:
  ///   - data: The root elements.
  ///   - children: Returns the children of an element, or `nil` for a leaf. Pass a key path such
  ///     as `\.children` or a closure.
  ///   - selection: The identifier of the selected element, or `nil` if nothing is selected.
  ///   - expansion: The identifiers of the expanded elements. When omitted, the outline keeps its
  ///     expansion state internally and starts fully collapsed.
  ///   - rowContent: Builds the content of the row for an element.
  public init(
    _ data: Data,
    children: @escaping (Element) -> [Element]?,
    selection: Binding<ID?>,
    expansion: Binding<Set<ID>>? = nil,
    @ViewBuilder rowContent: @escaping (Element) -> RowContent
  ) {
    self.init(
      data, children: children, selection: .single(selection), expansion: expansion,
      rowContent: rowContent)
  }

  /// Creates an outline that allows selecting several elements at once.
  ///
  /// - Parameters:
  ///   - data: The root elements.
  ///   - children: Returns the children of an element, or `nil` for a leaf. Pass a key path such
  ///     as `\.children` or a closure.
  ///   - selection: The identifiers of the selected elements.
  ///   - expansion: The identifiers of the expanded elements. When omitted, the outline keeps its
  ///     expansion state internally and starts fully collapsed.
  ///   - rowContent: Builds the content of the row for an element.
  public init(
    _ data: Data,
    children: @escaping (Element) -> [Element]?,
    selection: Binding<Set<ID>>,
    expansion: Binding<Set<ID>>? = nil,
    @ViewBuilder rowContent: @escaping (Element) -> RowContent
  ) {
    self.init(
      data, children: children, selection: .multiple(selection), expansion: expansion,
      rowContent: rowContent)
  }

  /// Creates an outline without selection.
  ///
  /// - Parameters:
  ///   - data: The root elements.
  ///   - children: Returns the children of an element, or `nil` for a leaf. Pass a key path such
  ///     as `\.children` or a closure.
  ///   - expansion: The identifiers of the expanded elements. When omitted, the outline keeps its
  ///     expansion state internally and starts fully collapsed.
  ///   - rowContent: Builds the content of the row for an element.
  public init(
    _ data: Data,
    children: @escaping (Element) -> [Element]?,
    expansion: Binding<Set<ID>>? = nil,
    @ViewBuilder rowContent: @escaping (Element) -> RowContent
  ) {
    self.init(
      data, children: children, selection: .none, expansion: expansion, rowContent: rowContent)
  }

  private init(
    _ data: Data,
    children: @escaping (Element) -> [Element]?,
    selection: OutlineSelection<ID>,
    expansion: Binding<Set<ID>>?,
    rowContent: @escaping (Element) -> RowContent
  ) {
    self.data = data
    self.children = children
    self.selection = selection
    self.expansion = expansion
    self.rowContent = rowContent
  }

  /// The content and behavior of the view.
  public var body: some View {
    ListOutlineRenderer(
      tree: OutlineTree(data, children: children),
      selection: selection,
      expansion: expansion ?? $internalExpansion,
      rowContent: rowContent)
  }
}

/// How an outline binds its selection.
enum OutlineSelection<ID: Hashable> {
  case none
  case single(Binding<ID?>)
  case multiple(Binding<Set<ID>>)
}
