#if os(macOS)
  import AppKit
  import SwiftUI

  /// Renders an outline with a native `NSOutlineView` in source-list style.
  ///
  /// The host's bindings stay the source of truth. Every update applies the latest snapshot,
  /// expansion and selection to the outline; user interaction writes back into the bindings.
  struct AppKitOutlineRenderer<Element: Identifiable, RowContent: View>: NSViewRepresentable
  where Element.ID: Sendable {
    typealias ID = Element.ID

    let tree: OutlineTree<Element>
    let selection: OutlineSelection<ID>
    @Binding var expansion: Set<ID>
    let behavior: OutlineBehavior<Element>
    let rowContent: (Element) -> RowContent

    func makeCoordinator() -> OutlineCoordinator<Element, RowContent> {
      OutlineCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("GMSnagNav.Column"))
      column.resizingMask = .autoresizingMask

      let outlineView = NSOutlineView()
      outlineView.addTableColumn(column)
      outlineView.outlineTableColumn = column
      outlineView.headerView = nil
      outlineView.style = .sourceList
      outlineView.rowSizeStyle = .default
      outlineView.floatsGroupRows = false
      outlineView.autosaveExpandedItems = false
      outlineView.allowsEmptySelection = true
      outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle
      outlineView.dataSource = context.coordinator
      outlineView.delegate = context.coordinator

      let scrollView = NSScrollView()
      scrollView.documentView = outlineView
      scrollView.hasVerticalScroller = true
      scrollView.autohidesScrollers = true
      scrollView.drawsBackground = false
      scrollView.borderType = .noBorder

      context.coordinator.outlineView = outlineView
      context.coordinator.update(with: self)
      return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
      context.coordinator.update(with: self)
    }
  }

  /// Data source and delegate of the outline; translates between AppKit and the host's bindings.
  @MainActor
  final class OutlineCoordinator<Element: Identifiable, RowContent: View>: NSObject,
    NSOutlineViewDataSource, NSOutlineViewDelegate
  where Element.ID: Sendable {
    typealias ID = Element.ID
    typealias Renderer = AppKitOutlineRenderer<Element, RowContent>

    weak var outlineView: NSOutlineView?
    private var renderer: Renderer?
    private var tree = OutlineTree<Element>([], children: { _ in nil })
    private var boxes: [ID: NodeBox<ID>] = [:]
    /// Set while the coordinator changes the outline itself, so AppKit's callbacks for those
    /// changes are not mistaken for user interaction and written back into the bindings.
    private var isApplyingUpdate = false

    // MARK: Updates

    /// Applies a new snapshot, expansion and selection to the outline.
    func update(with renderer: Renderer) {
      self.renderer = renderer
      tree = renderer.tree
      boxes = boxes.filter { tree.contains($0.key) }
      guard let outlineView else { return }

      isApplyingUpdate = true
      defer { isApplyingUpdate = false }

      switch renderer.selection {
      case .none, .single: outlineView.allowsMultipleSelection = false
      case .multiple: outlineView.allowsMultipleSelection = true
      }

      outlineView.reloadData()
      applyExpansion(renderer.expansion)
      applySelection(selectedIDs(in: renderer.selection))
    }

    private func applyExpansion(_ desired: Set<ID>) {
      guard let outlineView else { return }
      let current = Set(
        boxes.values.filter { outlineView.isItemExpanded($0) }.map(\.id))
      let changes = tree.expansionChanges(from: current, to: desired)
      for id in changes.collapse {
        outlineView.collapseItem(box(for: id))
      }
      // Items below a collapsed parent are not loaded and ignore `expandItem`; they are expanded
      // when their parent opens, in `outlineViewItemDidExpand(_:)`.
      for id in changes.expand {
        outlineView.expandItem(box(for: id))
      }
    }

    private func applySelection(_ ids: Set<ID>) {
      guard let outlineView else { return }
      let rows = IndexSet(ids.map { outlineView.row(forItem: box(for: $0)) }.filter { $0 >= 0 })
      if rows != outlineView.selectedRowIndexes {
        outlineView.selectRowIndexes(rows, byExtendingSelection: false)
      }
    }

    private func selectedIDs(in selection: OutlineSelection<ID>) -> Set<ID> {
      switch selection {
      case .none: []
      case .single(let binding): binding.wrappedValue.map { [$0] } ?? []
      case .multiple(let binding): binding.wrappedValue
      }
    }

    // MARK: Items

    private func box(for id: ID) -> NodeBox<ID> {
      if let box = boxes[id] { return box }
      let box = NodeBox(id)
      boxes[id] = box
      return box
    }

    private func id(of item: Any?) -> ID? {
      (item as? NodeBox<ID>)?.id
    }

    // MARK: NSOutlineViewDataSource

    func outlineView(_ outlineView: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
      tree.children(of: id(of: item)).count
    }

    func outlineView(_ outlineView: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
      box(for: tree.children(of: id(of: item))[index])
    }

    func outlineView(_ outlineView: NSOutlineView, isItemExpandable item: Any) -> Bool {
      guard let id = id(of: item) else { return false }
      // Empty containers show no disclosure triangle, matching the SwiftUI renderer.
      return !tree.children(of: id).isEmpty
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(
      _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
    ) -> NSView? {
      guard let renderer, let id = id(of: item), let element = tree.element(id) else {
        return nil
      }
      let cell =
        outlineView.makeView(withIdentifier: HostingCellView.reuseIdentifier, owner: nil)
        as? HostingCellView ?? HostingCellView()
      cell.show(AnyView(renderer.rowContent(element)))
      return cell
    }

    func outlineView(
      _ outlineView: NSOutlineView,
      selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
    ) -> IndexSet {
      guard let renderer else { return [] }
      if case .none = renderer.selection { return [] }
      return proposedSelectionIndexes.filteredIndexSet { row in
        guard let id = id(of: outlineView.item(atRow: row)), let element = tree.element(id)
        else { return false }
        return renderer.behavior.canSelect(element)
      }
    }

    func outlineViewSelectionDidChange(_ notification: Notification) {
      guard !isApplyingUpdate, let renderer, let outlineView else { return }
      let ids = outlineView.selectedRowIndexes.compactMap { id(of: outlineView.item(atRow: $0)) }
      switch renderer.selection {
      case .none:
        break
      case .single(let binding):
        if binding.wrappedValue != ids.first { binding.wrappedValue = ids.first }
      case .multiple(let binding):
        let selected = Set(ids)
        if binding.wrappedValue != selected { binding.wrappedValue = selected }
      }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
      guard let renderer, let outlineView, let id = expandedOrCollapsedID(in: notification)
      else { return }
      if !isApplyingUpdate, !renderer.expansion.contains(id) {
        renderer.expansion.insert(id)
      }
      // Restore the expansion of children that were expanded while this item was collapsed.
      let wasApplying = isApplyingUpdate
      isApplyingUpdate = true
      defer { isApplyingUpdate = wasApplying }
      for child in tree.children(of: id) where renderer.expansion.contains(child) {
        outlineView.expandItem(box(for: child))
      }
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
      guard !isApplyingUpdate, let renderer, let id = expandedOrCollapsedID(in: notification)
      else { return }
      if renderer.expansion.contains(id) {
        renderer.expansion.remove(id)
      }
    }

    /// Reads the item from an expansion notification; AppKit documents the key as `"NSObject"`.
    private func expandedOrCollapsedID(in notification: Notification) -> ID? {
      id(of: notification.userInfo?["NSObject"])
    }
  }
#endif
