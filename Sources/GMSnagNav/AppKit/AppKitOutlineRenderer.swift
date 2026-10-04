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
    let appearance: OutlineAppearance
    var springLoading = SpringLoadingBehavior.automatic
    let rowContent: (Element) -> RowContent

    func makeCoordinator() -> OutlineCoordinator<Element, RowContent> {
      OutlineCoordinator()
    }

    func makeNSView(context: Context) -> NSScrollView {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("GMSnagNav.Column"))
      column.resizingMask = .autoresizingMask

      let outlineView = SnagOutlineView()
      outlineView.addTableColumn(column)
      outlineView.outlineTableColumn = column
      outlineView.headerView = nil
      outlineView.rowSizeStyle = .default
      outlineView.floatsGroupRows = false
      outlineView.autosaveExpandedItems = false
      outlineView.allowsEmptySelection = true
      outlineView.columnAutoresizingStyle = .uniformColumnAutoresizingStyle

      let scrollView = NSScrollView()
      scrollView.documentView = outlineView
      scrollView.hasVerticalScroller = true
      scrollView.autohidesScrollers = true
      scrollView.drawsBackground = false
      scrollView.borderType = .noBorder

      context.coordinator.attach(to: outlineView)
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

    private(set) weak var outlineView: NSOutlineView?
    private var renderer: Renderer?
    private var tree = OutlineTree<Element>([], children: { _ in nil })
    private var boxes: [ID: NodeBox<ID>] = [:]
    /// The private pasteboard type of rows dragged within the outline.
    static var draggedRowType: NSPasteboard.PasteboardType {
      NSPasteboard.PasteboardType("io.github.kerker00.gmsnagnav.outline-row")
    }
    /// The elements of the current drag session, keyed by the token written to the pasteboard.
    ///
    /// Only tokens travel on the pasteboard, so identifiers need not be `Codable`, and drags from
    /// other outlines or apps — whose tokens are unknown here — are ignored.
    private var draggedIDsByToken: [String: ID] = [:]
    /// The host's answers for the current drag and snapshot.
    private var dropCache = DropResolutionCache<ID>()
    /// Collapsed elements opened temporarily by hovering over them during the current drag.
    private var springLoaded: [ID] = []
    /// The element the pointer rests on during a drag, and the pending task that opens it.
    private var springLoadCandidate: ID?
    private var springLoadTask: Task<Void, Never>?
    /// Finishes once the pending spring-loading has opened its element or was cancelled, for tests.
    func springLoadingSettled() async {
      await springLoadTask?.value
    }
    /// Replaces the system's spring-loading delay, for tests.
    var springLoadingDelayOverride: Duration?
    /// Set while spring-loading opens or closes elements; such changes never reach the binding.
    private var isSpringLoading = false
    /// Whether the outline has loaded a snapshot; the first one is loaded without animation.
    private var hasLoaded = false
    /// Above this many steps, reloading everything is cheaper and calmer than animating them.
    static var maximumAnimatedChanges: Int { 250 }
    /// Set while the coordinator changes the outline itself, so AppKit's callbacks for those
    /// changes are not mistaken for user interaction and written back into the bindings.
    private var isApplyingUpdate = false
    private let clickTarget = OutlineClickTarget()
    /// A single click on an unselectable container toggles it once the double-click interval has
    /// passed, so a double-click can still run the primary action instead.
    private var pendingToggle: Task<Void, Never>?

    /// Connects the coordinator to an outline view as its data source, delegate and click target.
    func attach(to outlineView: NSOutlineView) {
      self.outlineView = outlineView
      outlineView.dataSource = self
      outlineView.delegate = self
      clickTarget.onClick = { [weak self] in self?.handleClick() }
      clickTarget.onDoubleClick = { [weak self] in self?.handleDoubleClick() }
      outlineView.target = clickTarget
      outlineView.action = #selector(OutlineClickTarget.click(_:))
      outlineView.doubleAction = #selector(OutlineClickTarget.doubleClick(_:))
      (outlineView as? SnagOutlineView)?.onReturn = { [weak self] in
        self?.handleReturn() ?? false
      }
      outlineView.registerForDraggedTypes([Self.draggedRowType])
      outlineView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
      outlineView.setDraggingSourceOperationMask([], forLocal: false)
    }

    // MARK: Updates

    /// Applies a new snapshot, expansion and selection to the outline.
    func update(with renderer: Renderer) {
      self.renderer = renderer
      let oldTree = tree
      renderer.behavior.reportDuplicateIDs(in: renderer.tree, previous: oldTree)
      tree = renderer.tree
      dropCache.removeAll()
      guard let outlineView else {
        boxes = boxes.filter { tree.contains($0.key) }
        return
      }

      isApplyingUpdate = true
      defer { isApplyingUpdate = false }

      switch renderer.selection {
      case .none, .single: outlineView.allowsMultipleSelection = false
      case .multiple: outlineView.allowsMultipleSelection = true
      }
      let reindented = applyAppearance(renderer.appearance, to: outlineView)

      applyStructure(from: oldTree, to: outlineView, reloading: reindented)
      boxes = boxes.filter { tree.contains($0.key) }
      refreshVisibleRows()
      applyExpansion(renderer.expansion)
      applySelection(selectedIDs(in: renderer.selection))
    }

    /// Brings the outline's rows from the old snapshot to the current one, animated when possible.
    ///
    /// - Parameter reloading: Reloads all rows instead, for changes that affect every row.
    private func applyStructure(
      from oldTree: OutlineTree<Element>, to outlineView: NSOutlineView, reloading: Bool = false
    ) {
      guard hasLoaded, !reloading else {
        hasLoaded = true
        outlineView.reloadData()
        return
      }
      let loaded = Set(boxes.values.filter { outlineView.isItemExpanded($0) }.map(\.id))
      let changes = tree.changes(from: oldTree, loaded: loaded)
      guard !changes.isEmpty else { return }
      guard changes.count <= Self.maximumAnimatedChanges else {
        outlineView.reloadData()
        return
      }

      // Starting the update can make AppKit load rows it has not cached yet — for example to ask
      // the delegate which rows are group rows — while its row counts still describe the old
      // snapshot. Let the data source answer with that snapshot until the update has begun.
      let newTree = tree
      tree = oldTree
      outlineView.beginUpdates()
      tree = newTree
      // From here on the data source answers with the new snapshot; every step keeps the outline
      // consistent with it for the rows it has touched so far.
      for change in changes {
        switch change {
        case .remove(let parent, let index):
          outlineView.removeItems(
            at: [index], inParent: parent.map(box(for:)), withAnimation: .effectFade)
        case .insert(_, let parent, let index):
          outlineView.insertItems(
            at: [index], inParent: parent.map(box(for:)), withAnimation: .effectFade)
        case .move(_, let fromParent, let fromIndex, let toParent, let toIndex):
          outlineView.moveItem(
            at: fromIndex, inParent: fromParent.map(box(for:)),
            to: toIndex, inParent: toParent.map(box(for:)))
        case .reload(let id):
          outlineView.reloadItem(box(for: id), reloadChildren: false)
        }
      }
      outlineView.endUpdates()
    }

    /// Shows the current content in the visible rows, whose elements may have changed in place.
    private func refreshVisibleRows() {
      guard let outlineView else { return }
      for row in 0..<outlineView.numberOfRows {
        guard
          let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: false)
            as? HostingCellView,
          let id = id(of: outlineView.item(atRow: row)),
          let content = rowContent(for: id)
        else { continue }
        cell.show(content)
      }
    }

    /// The host's row content for an element, with the context menu attached.
    private func rowContent(for id: ID) -> AnyView? {
      guard let renderer, let element = tree.element(id) else { return nil }
      let content =
        if let title = renderer.behavior.sectionTitle(of: id, in: tree) {
          AnyView(OutlineSectionHeader(title: title))
        } else {
          AnyView(renderer.rowContent(element))
        }
      let session = renderer.behavior.renameSession(for: id, in: tree) { [weak self] in
        self?.takeFocusBack()
      }
      let row = AnyView(content.environment(\.outlineRenameSession, session))
      guard let menu = renderer.behavior.contextMenu else { return row }
      let ids = activatedIDs(for: id)
      return AnyView(row.contextMenu { menu(ids) })
    }

    /// Applies the style, the host's configuration and the indentation.
    ///
    /// - Returns: Whether the indentation changed. AppKit indents only rows and disclosure
    ///   triangles it creates from then on, so the visible rows need to be reloaded.
    private func applyAppearance(
      _ appearance: OutlineAppearance, to outlineView: NSOutlineView
    ) -> Bool {
      let style: NSTableView.Style =
        switch appearance.style {
        case .automatic, .sidebar: .sourceList
        case .plain: .plain
        }
      if outlineView.style != style { outlineView.style = style }
      appearance.appKitConfiguration?(outlineView)
      // After the host's configuration: AppKit resets the indentation when the row size changes.
      guard outlineView.indentationPerLevel != appearance.indentation else { return false }
      outlineView.indentationPerLevel = appearance.indentation
      return true
    }

    private func applyExpansion(_ desired: Set<ID>) {
      guard let outlineView else { return }
      let current = Set(
        boxes.values.filter { outlineView.isItemExpanded($0) }.map(\.id))
      let changes = tree.expansionChanges(from: current, to: desired)
      // Spring-loaded elements stay open until the drag ends, even though the binding lacks them.
      for id in changes.collapse where !springLoaded.contains(id) {
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
      // Empty containers show no disclosure triangle, matching the UIKit renderer.
      return !tree.children(of: id).isEmpty
    }

    // MARK: Dragging

    func outlineView(
      _ outlineView: NSOutlineView, pasteboardWriterForItem item: Any
    ) -> NSPasteboardWriting? {
      guard let canDrag = renderer?.behavior.canDrag, let id = id(of: item),
        let element = tree.element(id), canDrag(element)
      else { return nil }
      let token = UUID().uuidString
      draggedIDsByToken[token] = id
      let pasteboardItem = NSPasteboardItem()
      pasteboardItem.setString(token, forType: Self.draggedRowType)
      return pasteboardItem
    }

    func outlineView(
      _ outlineView: NSOutlineView, draggingSession session: NSDraggingSession,
      endedAt screenPoint: NSPoint, operation: NSDragOperation
    ) {
      draggedIDsByToken.removeAll()
      dropCache.removeAll()
      endSpringLoading()
    }

    // MARK: Spring-loading

    /// The delay before a hovered element opens, or `nil` if spring-loading is off.
    ///
    /// Follows the system's spring-loading preference unless the host set
    /// `springLoadingBehavior(_:)` explicitly.
    private var springLoadingDelay: Duration? {
      guard let renderer, renderer.springLoading != .disabled else { return nil }
      if let springLoadingDelayOverride { return springLoadingDelayOverride }
      let defaults = UserDefaults.standard
      if renderer.springLoading == .automatic,
        defaults.object(forKey: "com.apple.springing.enabled") as? Bool == false
      {
        return nil
      }
      let delay = defaults.double(forKey: "com.apple.springing.delay")
      return .seconds(delay > 0 ? delay : 0.5)
    }

    /// Opens collapsed elements the pointer rests on and closes the ones it has left.
    func updateSpringLoading(hovering item: Any?, childIndex: Int) {
      let target = target(item: item, childIndex: childIndex)
      for id in tree.springLoadedToClose(springLoaded, targetParent: target.parent) {
        springLoaded.removeAll { $0 == id }
        setSpringLoaded(id, expanded: false)
      }

      var candidate: ID?
      if childIndex == NSOutlineViewDropOnItemIndex, let id = id(of: item),
        !tree.children(of: id).isEmpty, outlineView?.isItemExpanded(box(for: id)) == false
      {
        candidate = id
      }
      guard candidate != springLoadCandidate else { return }
      springLoadTask?.cancel()
      springLoadCandidate = candidate
      guard let candidate, let delay = springLoadingDelay else { return }

      springLoadTask = Task { [weak self] in
        try? await Task.sleep(for: delay)
        guard !Task.isCancelled, let self, self.springLoadCandidate == candidate else { return }
        self.springLoaded.append(candidate)
        self.setSpringLoaded(candidate, expanded: true)
      }
    }

    /// Closes what spring-loading opened, unless the host expanded it in the meantime — for
    /// example to reveal the elements just dropped into it.
    func endSpringLoading() {
      springLoadTask?.cancel()
      springLoadTask = nil
      springLoadCandidate = nil
      let expansion = renderer?.expansion ?? []
      let toClose = tree.springLoadedToClose(springLoaded, targetParent: nil)
      springLoaded.removeAll()
      for id in toClose where !expansion.contains(id) {
        setSpringLoaded(id, expanded: false)
      }
    }

    private func setSpringLoaded(_ id: ID, expanded: Bool) {
      // The host may have removed the element during the drag.
      guard let outlineView, tree.contains(id) else { return }
      isSpringLoading = true
      defer { isSpringLoading = false }
      // Not through the animator: the expansion notifications must arrive while
      // `isSpringLoading` is set, so the temporary change never reaches the binding.
      if expanded {
        outlineView.expandItem(box(for: id))
      } else {
        outlineView.collapseItem(box(for: id))
      }
    }

    func outlineView(
      _ outlineView: NSOutlineView, validateDrop info: NSDraggingInfo, proposedItem item: Any?,
      proposedChildIndex index: Int
    ) -> NSDragOperation {
      let ids = draggedIDs(on: info.draggingPasteboard)
      guard !ids.isEmpty else { return [] }
      updateSpringLoading(hovering: item, childIndex: index)
      guard
        let drop = resolveDrop(
          of: ids, onto: item, childIndex: index, copying: Self.isCopyRequested(by: info))
      else { return [] }
      if drop.proposal.target != target(item: item, childIndex: index) {
        outlineView.setDropItem(
          drop.proposal.target.parent.map(box(for:)),
          dropChildIndex: drop.proposal.target.childIndex ?? NSOutlineViewDropOnItemIndex)
      }
      return drop.operation.dragOperation
    }

    func outlineView(
      _ outlineView: NSOutlineView, acceptDrop info: NSDraggingInfo, item: Any?,
      childIndex index: Int
    ) -> Bool {
      performDrop(
        of: draggedIDs(on: info.draggingPasteboard), onto: item, childIndex: index,
        copying: Self.isCopyRequested(by: info))
    }

    /// Whether the user holds the Option key, which limits the drag to copying.
    static func isCopyRequested(by info: NSDraggingInfo) -> Bool {
      let mask = info.draggingSourceOperationMask
      return mask.contains(.copy) && !mask.contains(.move)
    }

    /// Asks the host where and how dragged elements may be dropped at AppKit's proposed position.
    ///
    /// - Returns: The proposal — with a redirected target if the host asked for one — and the
    ///   accepted operation, or `nil` if the drop is not allowed.
    func resolveDrop(
      of ids: [ID], onto item: Any?, childIndex: Int, copying: Bool = false
    ) -> (proposal: OutlineDropProposal<ID>, operation: OutlineDropOperation)? {
      guard let renderer, let drop = renderer.behavior.drop, !ids.isEmpty else { return nil }
      let target = target(item: item, childIndex: childIndex)
      return dropCache.resolution(for: ids, target: target, isCopyRequested: copying) {
        drop.resolve(
          draggedIDs: ids, target: target, tree: tree, expanded: renderer.expansion,
          isCopyRequested: copying)
      }
    }

    /// Validates the drop once more and lets the host perform it.
    func performDrop(
      of ids: [ID], onto item: Any?, childIndex: Int, copying: Bool = false
    ) -> Bool {
      guard let drop = renderer?.behavior.drop,
        let resolved = resolveDrop(of: ids, onto: item, childIndex: childIndex, copying: copying)
      else { return false }
      return drop.perform(resolved.proposal, resolved.operation)
    }

    private func target(item: Any?, childIndex: Int) -> OutlineDropTarget<ID> {
      let parent = id(of: item)
      return childIndex == NSOutlineViewDropOnItemIndex
        ? OutlineDropTarget(parent: parent, placement: .onto)
        : .insert(into: parent, at: childIndex)
    }

    /// The elements of this outline that are being dragged on `pasteboard`, in pasteboard order.
    func draggedIDs(on pasteboard: NSPasteboard) -> [ID] {
      draggedIDs(in: pasteboard.pasteboardItems ?? [])
    }

    /// Resolves this outline's private drag tokens without depending on a pasteboard server.
    func draggedIDs(in items: [NSPasteboardItem]) -> [ID] {
      items.compactMap { item in
        item.string(forType: Self.draggedRowType).flatMap { draggedIDsByToken[$0] }
      }
    }

    // MARK: NSOutlineViewDelegate

    func outlineView(
      _ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any
    ) -> NSView? {
      guard let id = id(of: item), let content = rowContent(for: id) else { return nil }
      let cell =
        outlineView.makeView(withIdentifier: HostingCellView.reuseIdentifier, owner: nil)
        as? HostingCellView ?? HostingCellView()
      cell.show(content)
      return cell
    }

    func outlineView(
      _ outlineView: NSOutlineView,
      selectionIndexesForProposedSelection proposedSelectionIndexes: IndexSet
    ) -> IndexSet {
      guard let renderer else { return [] }
      if case .none = renderer.selection { return [] }
      return proposedSelectionIndexes.filteredIndexSet { row in
        guard let id = id(of: outlineView.item(atRow: row)) else { return false }
        return renderer.behavior.canSelect(id, in: tree)
      }
    }

    func outlineView(
      _ outlineView: NSOutlineView, typeSelectStringFor tableColumn: NSTableColumn?, item: Any
    ) -> String? {
      typeSelectText(for: id(of: item))
    }

    /// The text that type select matches for an element, or `nil` to skip its row: without the
    /// host's text, and for rows that cannot be selected.
    func typeSelectText(for id: ID?) -> String? {
      guard let renderer, let text = renderer.behavior.typeSelectText,
        let id, let element = tree.element(id), renderer.behavior.canSelect(id, in: tree)
      else { return nil }
      if case .none = renderer.selection { return nil }
      return text(element)
    }

    func outlineView(_ outlineView: NSOutlineView, isGroupItem item: Any) -> Bool {
      guard let renderer, let id = id(of: item) else { return false }
      return renderer.behavior.sectionTitle(of: id, in: tree) != nil
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
      if !isApplyingUpdate, !isSpringLoading, !renderer.expansion.contains(id) {
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
      guard !isApplyingUpdate, !isSpringLoading, let renderer,
        let id = expandedOrCollapsedID(in: notification)
      else { return }
      if renderer.expansion.contains(id) {
        renderer.expansion.remove(id)
      }
    }

    // MARK: Clicks and keys

    /// The elements an action on `id` applies to: the selection if `id` is part of it, otherwise
    /// `id` alone.
    private func activatedIDs(for id: ID) -> Set<ID> {
      guard let renderer else { return [id] }
      let selected = selectedIDs(in: renderer.selection)
      return selected.contains(id) ? selected : [id]
    }

    private func handleClick() {
      guard let renderer, let outlineView else { return }
      let row = outlineView.clickedRow
      guard row >= 0, let id = id(of: outlineView.item(atRow: row)),
        !renderer.behavior.canSelect(id, in: tree), !tree.children(of: id).isEmpty
      else { return }

      // The disclosure triangle toggles on its own; do not toggle a second time.
      if let event = NSApp.currentEvent {
        let location = outlineView.convert(event.locationInWindow, from: nil)
        if outlineView.frameOfOutlineCell(atRow: row).contains(location) { return }
      }

      guard renderer.behavior.primaryAction != nil else {
        toggle(id)
        return
      }
      pendingToggle?.cancel()
      pendingToggle = Task { [weak self] in
        try? await Task.sleep(for: .seconds(NSEvent.doubleClickInterval))
        guard !Task.isCancelled else { return }
        self?.toggle(id)
      }
    }

    private func handleDoubleClick() {
      pendingToggle?.cancel()
      pendingToggle = nil
      guard let primaryAction = renderer?.behavior.primaryAction, let outlineView else { return }
      let row = outlineView.clickedRow
      guard row >= 0, let id = id(of: outlineView.item(atRow: row)) else { return }
      primaryAction(activatedIDs(for: id))
    }

    /// Makes the outline the first responder again after renaming ended with the keyboard;
    /// otherwise no view keeps the focus, the selection turns gray, and Return no longer reaches
    /// the outline.
    private func takeFocusBack() {
      // After SwiftUI has removed the text field, which would otherwise keep the focus.
      Task { @MainActor [weak self] in
        guard let outlineView = self?.outlineView else { return }
        outlineView.window?.makeFirstResponder(outlineView)
      }
    }

    /// Renames the selected row, as in the Finder, or runs the primary action for the selection;
    /// returns whether it handled the key press.
    func handleReturn() -> Bool {
      guard let renderer else { return false }
      let selected = selectedIDs(in: renderer.selection)
      if selected.count == 1, let id = selected.first,
        renderer.behavior.startRenaming(id, in: tree)
      {
        return true
      }
      guard let primaryAction = renderer.behavior.primaryAction, !selected.isEmpty else {
        return false
      }
      primaryAction(selected)
      return true
    }

    private func toggle(_ id: ID) {
      guard let outlineView else { return }
      let item = box(for: id)
      if outlineView.isItemExpanded(item) {
        outlineView.animator().collapseItem(item)
      } else {
        outlineView.animator().expandItem(item)
      }
    }

    /// Reads the item from an expansion notification; AppKit documents the key as `"NSObject"`.
    private func expandedOrCollapsedID(in notification: Notification) -> ID? {
      id(of: notification.userInfo?["NSObject"])
    }
  }

  extension OutlineDropOperation {
    /// The matching AppKit drag operation.
    var dragOperation: NSDragOperation {
      switch self {
      case .move: .move
      case .copy: .copy
      }
    }
  }
#endif
