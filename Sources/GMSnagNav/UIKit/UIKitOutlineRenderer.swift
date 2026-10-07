#if os(iOS)
  import SwiftUI
  import UIKit

  /// Renders an outline with a native `UICollectionView` list, the iOS counterpart of
  /// `NSOutlineView`.
  ///
  /// The host's bindings stay the source of truth. Every update applies the latest snapshot,
  /// expansion and selection; UIKit's diffable data source animates the difference. User
  /// interaction writes back into the bindings.
  struct UIKitOutlineRenderer<Element: Identifiable, RowContent: View>: UIViewRepresentable
  where Element.ID: Sendable {
    typealias ID = Element.ID

    let tree: OutlineTree<Element>
    let selection: OutlineSelection<ID>
    @Binding var expansion: Set<ID>
    let behavior: OutlineBehavior<Element>
    let appearance: OutlineAppearance
    var springLoading = SpringLoadingBehavior.automatic
    let rowContent: (Element) -> RowContent

    func makeCoordinator() -> UIKitOutlineCoordinator<Element, RowContent> {
      UIKitOutlineCoordinator()
    }

    func makeUIView(context: Context) -> UICollectionView {
      let collectionView = SnagCollectionView(
        frame: .zero,
        collectionViewLayout: UIKitOutlineCoordinator<Element, RowContent>.layout(
          for: appearance.style))
      collectionView.backgroundColor = .clear
      context.coordinator.attach(to: collectionView)
      context.coordinator.update(
        with: self, layoutDirection: context.environment.layoutDirection,
        dynamicTypeSize: context.environment.dynamicTypeSize, locale: context.environment.locale)
      return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
      context.coordinator.update(
        with: self, layoutDirection: context.environment.layoutDirection,
        dynamicTypeSize: context.environment.dynamicTypeSize, locale: context.environment.locale)
    }
  }

  /// Data source owner and delegate of the collection view; translates between UIKit and the
  /// host's bindings.
  @MainActor
  final class UIKitOutlineCoordinator<Element: Identifiable, RowContent: View>: NSObject,
    UICollectionViewDelegate, UICollectionViewDragDelegate, UICollectionViewDropDelegate
  where Element.ID: Sendable {
    typealias ID = Element.ID
    typealias Renderer = UIKitOutlineRenderer<Element, RowContent>

    private(set) weak var collectionView: UICollectionView?
    private var dataSource: UICollectionViewDiffableDataSource<Int, ID>?
    private var renderer: Renderer?
    private var tree = OutlineTree<Element>([], children: { _ in nil })
    private var appliedStyle: SnagOutlineStyle?
    private var hasLoaded = false
    /// Set while the coordinator changes the collection view itself, so UIKit's callbacks for
    /// those changes are not mistaken for user interaction and written back into the bindings.
    private var isApplyingUpdate = false
    /// Headers may receive focus without entering the host's selection.
    private(set) var focusedItemID: ID?
    private var lastAppliedSelection: Set<ID> = []
    private var layoutDirection = LayoutDirection.leftToRight
    private var dynamicTypeSizeOverride: DynamicTypeSize?
    private var locale = Locale.current

    /// A list layout in the style's appearance, asking `swipeActions` for each row's swipe
    /// actions at the leading and trailing edge.
    static func layout(
      for style: SnagOutlineStyle,
      swipeActions: ((IndexPath, HorizontalEdge) -> UISwipeActionsConfiguration?)? = nil
    ) -> UICollectionViewCompositionalLayout {
      let appearance: UICollectionLayoutListConfiguration.Appearance =
        switch style {
        case .automatic, .sidebar: .sidebar
        case .plain: .plain
        }
      var configuration = UICollectionLayoutListConfiguration(appearance: appearance)
      configuration.backgroundColor = .clear
      if let swipeActions {
        configuration.leadingSwipeActionsConfigurationProvider = { swipeActions($0, .leading) }
        configuration.trailingSwipeActionsConfigurationProvider = { swipeActions($0, .trailing) }
      }
      return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    /// Connects the coordinator to a collection view as its data source owner and delegate.
    func attach(to collectionView: UICollectionView) {
      self.collectionView = collectionView
      collectionView.delegate = self
      collectionView.dragDelegate = self
      collectionView.dropDelegate = self
      collectionView.allowsFocus = true
      collectionView.selectionFollowsFocus = true
      if let collectionView = collectionView as? SnagCollectionView {
        collectionView.canHandleKeyboardAction = { [weak self] action in
          self?.canHandleKeyboardAction(action) ?? false
        }
        collectionView.onKeyboardAction = { [weak self] action in
          self?.handleKeyboardAction(action)
        }
      }

      let registration = UICollectionView.CellRegistration<UICollectionViewListCell, ID> {
        [weak self] cell, _, id in
        self?.configure(cell, for: id)
      }
      let dataSource = UICollectionViewDiffableDataSource<Int, ID>(
        collectionView: collectionView
      ) { collectionView, indexPath, id in
        collectionView.dequeueConfiguredReusableCell(using: registration, for: indexPath, item: id)
      }
      dataSource.sectionSnapshotHandlers.willExpandItem = { [weak self] id in
        self?.userChangedExpansion(of: id, expanded: true)
      }
      dataSource.sectionSnapshotHandlers.willCollapseItem = { [weak self] id in
        self?.userChangedExpansion(of: id, expanded: false)
      }
      self.dataSource = dataSource
    }

    // MARK: Updates

    /// Applies a new snapshot, expansion and selection to the collection view.
    func update(
      with renderer: Renderer, layoutDirection: LayoutDirection = .leftToRight,
      dynamicTypeSize: DynamicTypeSize = .large, locale: Locale = .current
    ) {
      let oldTree = tree
      self.renderer = renderer
      self.layoutDirection = layoutDirection
      self.locale = locale
      // Keep UIKit's live trait environment when the host uses the system size. Only forward
      // an explicit SwiftUI override; fixing every row to the initial size blocks trait changes.
      // An unattached collection view still reports an unspecified size, so compare with the
      // application's system preference instead of accidentally freezing rows during creation.
      let nativeSize = DynamicTypeSize(UIApplication.shared.preferredContentSizeCategory) ?? .large
      dynamicTypeSizeOverride = dynamicTypeSize == nativeSize ? nil : dynamicTypeSize
      renderer.behavior.reportDuplicateIDs(in: renderer.tree, previous: tree)
      tree = renderer.tree
      if let focusedItemID, !tree.contains(focusedItemID) { self.focusedItemID = nil }
      dropCache.removeAll()
      guard let collectionView, let dataSource else { return }
      collectionView.semanticContentAttribute =
        layoutDirection == .rightToLeft ? .forceRightToLeft : .forceLeftToRight
      (collectionView as? SnagCollectionView)?.outlineLayoutDirection =
        layoutDirection == .rightToLeft ? .rightToLeft : .leftToRight

      isApplyingUpdate = true
      defer { isApplyingUpdate = false }

      if appliedStyle != renderer.appearance.style {
        // Also on the first update: the layout from `makeUIView` cannot reach the coordinator for
        // swipe actions yet.
        collectionView.setCollectionViewLayout(
          Self.layout(for: renderer.appearance.style) { [weak self] indexPath, edge in
            self?.swipeActionsConfiguration(at: indexPath, edge: edge)
          },
          animated: false)
        appliedStyle = renderer.appearance.style
      }
      switch renderer.selection {
      case .none, .single: collectionView.allowsMultipleSelection = false
      case .multiple: collectionView.allowsMultipleSelection = true
      }
      // With a native menu — or none — UIKit shares the long press between dragging and the menu.
      // A SwiftUI menu lives in the hosted row, so the row starts drags itself, next to its menu;
      // the collection view's own drag would win the long press and hide that menu.
      collectionView.dragInteractionEnabled =
        renderer.behavior.canDrag != nil && !rowsDragThemselves

      let expanded = Set(displayedExpansion.filter { !tree.children(of: $0).isEmpty })
      let applied = dataSource.snapshot(for: 0)
      let expansionChanged = Set(applied.items.filter { applied.isExpanded($0) }) != expanded
      if !hasLoaded || !tree.hasSameStructure(as: oldTree) || expansionChanged {
        dataSource.apply(
          sectionSnapshot(expanded: expanded), to: 0, animatingDifferences: hasLoaded)
      }
      hasLoaded = true
      refreshVisibleCells()
      let selected = selectedIDs(in: renderer.selection)
      if selected != lastAppliedSelection, selected.count == 1 {
        focusedItemID = selected.first
      }
      lastAppliedSelection = selected
      applySelection(selected)
      reveal.hostSelected(
        selected, in: tree, expansion: renderer.$expansion,
        reveals: renderer.behavior.revealsSelection)
      scrollToRevealedElement()
    }

    /// Reveals elements the host selects; see `outlineRevealsSelection(_:)`.
    private var reveal = SelectionReveal<ID>()

    /// Scrolls the element waiting to be revealed into view once its row exists.
    private func scrollToRevealedElement() {
      guard let collectionView, let id = reveal.pending,
        let indexPath = dataSource?.indexPath(for: id),
        displayedRowsContain(id)
      else { return }
      reveal.didReveal()
      guard !collectionView.indexPathsForVisibleItems.contains(indexPath) else { return }
      collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: hasLoaded)
    }

    /// Whether the element's row is shown, i.e. all of its ancestors are expanded.
    private func displayedRowsContain(_ id: ID) -> Bool {
      tree.ancestors(of: id).allSatisfy(displayedExpansion.contains)
    }

    /// The whole tree as a hierarchical section snapshot; UIKit shows the children of expanded
    /// items and animates the difference to the previous snapshot.
    func sectionSnapshot(expanded: Set<ID>) -> NSDiffableDataSourceSectionSnapshot<ID> {
      var snapshot = NSDiffableDataSourceSectionSnapshot<ID>()
      snapshot.append(tree.roots)
      var pending = tree.roots
      while let parent = pending.popLast() {
        let children = tree.children(of: parent)
        guard !children.isEmpty else { continue }
        snapshot.append(children, to: parent)
        pending.append(contentsOf: children)
      }
      snapshot.expand(expanded.filter { !tree.children(of: $0).isEmpty })
      return snapshot
    }

    /// Shows the current content in visible cells, whose elements may have changed in place.
    ///
    /// Cells are matched to elements through the element each cell last showed, not through index
    /// paths: while a drag previews an insertion, UIKit moves cells away from their index paths.
    private func refreshVisibleCells() {
      guard let collectionView else { return }
      for case let cell as UICollectionViewListCell in collectionView.visibleCells {
        guard let id = cellElements[ObjectIdentifier(cell)], tree.contains(id) else { continue }
        configure(cell, for: id)
      }
    }

    /// The height a row's content takes at least; with the vertical margins, rows are 52 points
    /// tall, like those of a native sidebar list, and grow with larger text.
    static var rowMinimumContentHeight: CGFloat { 32 }

    /// The space above and below a row's content. Drop indicators reach into it, to the row's edge.
    static var rowVerticalMargin: CGFloat { 10 }

    /// The element each cell currently shows, keyed by the cell's identity.
    private var cellElements: [ObjectIdentifier: ID] = [:]

    private func configure(_ cell: UICollectionViewListCell, for id: ID) {
      cellElements[ObjectIdentifier(cell)] = id
      guard let renderer, let element = tree.element(id), let node = tree.node(id) else { return }
      let children = node.children ?? []
      let row = VisibleRow(
        id: id, depth: renderer.behavior.indentationDepth(of: id, in: tree), parent: node.parent,
        index: node.index, isExpandable: node.children != nil,
        isExpanded: !children.isEmpty && displayedExpansion.contains(id),
        childCount: children.count)
      let sectionTitle = renderer.behavior.sectionTitle(of: id, in: tree)
      let badge = renderer.behavior.badge?(element)
      // The row draws its own leading chevron and indentation: UIKit places its outline
      // disclosure on the trailing edge of sidebar lists and does not indent hosted content.
      let canDrag = rowsDragThemselves && renderer.behavior.canDrag?(element) == true
      // A native menu is shown by the collection view; only a SwiftUI menu lives in the row.
      let menu = renderer.behavior.contextMenuItems == nil ? renderer.behavior.contextMenu : nil
      let menuIDs = activatedIDs(for: id)
      let indicator = dropIndicator
      let indentation = renderer.appearance.indentation
      let togglesOnTap = !canSelect(id)
      let layoutDirection = self.layoutDirection
      let dynamicTypeSizeOverride = self.dynamicTypeSizeOverride
      let locale = self.locale
      cell.contentConfiguration = UIHostingConfiguration {
        let content = OutlineRowView(
          row: row, indentation: renderer.appearance.indentation, isExpanded: row.isExpanded,
          sectionTitle: sectionTitle, badge: badge, togglesOnTap: togglesOnTap,
          toggle: { [weak self] in self?.toggle(id) },
          content: renderer.rowContent(element)
        )
        .environment(\.layoutDirection, layoutDirection)
        .environment(\.locale, locale)
        .environment(
          \.outlineRenameSession,
          renderer.behavior.renameSession(for: id, in: tree) { [weak self] in
            self?.takeFocusBack()
          }
        )
        .frame(minHeight: Self.rowMinimumContentHeight)
        .modifier(RowMenu(menu: menu.map { menu in { menu(menuIDs) } }))
        .modifier(RowDrag(begin: canDrag ? { [weak self] in self?.beginDrag(from: id) } : nil))
        .background {
          if case .onto(id) = indicator {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(.tint.opacity(0.25))
              .padding(.horizontal, -8)
              .padding(.vertical, 4 - Self.rowVerticalMargin)
          }
        }
        .overlay(alignment: .bottomLeading) {
          if case .line(id, true, let depth) = indicator {
            InsertionLine(indent: CGFloat(depth) * indentation)
              .offset(y: Self.rowVerticalMargin + 1)
          }
        }
        .overlay(alignment: .topLeading) {
          if case .line(id, false, let depth) = indicator {
            InsertionLine(indent: CGFloat(depth) * indentation)
              .offset(y: -Self.rowVerticalMargin - 1)
          }
        }
        if let dynamicTypeSizeOverride {
          content.environment(\.dynamicTypeSize, dynamicTypeSizeOverride)
        } else {
          content
        }
      }
      .margins(.vertical, Self.rowVerticalMargin)
      cell.indentationLevel = 0
      cell.accessories = []
    }

    /// Expands or collapses an item on the user's behalf.
    private func toggle(_ id: ID) {
      guard !tree.children(of: id).isEmpty else { return }
      userChangedExpansion(of: id, expanded: !displayedExpansion.contains(id))
    }

    /// Whether rows start drags from their hosted content: only with a SwiftUI context menu.
    private var rowsDragThemselves: Bool {
      guard let behavior = renderer?.behavior else { return false }
      return behavior.contextMenuItems == nil && behavior.contextMenu != nil
    }

    // MARK: Expansion

    /// The expansion shown: the binding plus elements spring-loaded open during the current drag.
    var displayedExpansion: Set<ID> {
      (renderer?.expansion ?? []).union(springLoaded)
    }

    private func userChangedExpansion(of id: ID, expanded: Bool) {
      guard !isApplyingUpdate, let renderer else { return }
      if expanded, !renderer.expansion.contains(id) {
        renderer.expansion.insert(id)
      } else if !expanded, renderer.expansion.contains(id) {
        renderer.expansion.remove(id)
      }
    }

    // MARK: Selection

    private func selectedIDs(in selection: OutlineSelection<ID>) -> Set<ID> {
      switch selection {
      case .none: []
      case .single(let binding): binding.wrappedValue.map { [$0] } ?? []
      case .multiple(let binding): binding.wrappedValue
      }
    }

    private func applySelection(_ ids: Set<ID>) {
      guard let collectionView, let dataSource else { return }
      let desired = Set(ids.compactMap { dataSource.indexPath(for: $0) })
      let current = Set(collectionView.indexPathsForSelectedItems ?? [])
      for indexPath in current.subtracting(desired) {
        collectionView.deselectItem(at: indexPath, animated: false)
      }
      for indexPath in desired.subtracting(current) {
        collectionView.selectItem(at: indexPath, animated: false, scrollPosition: [])
      }
    }

    /// The identifiers of the currently selected items.
    var selectedItemIDs: [ID] {
      (collectionView?.indexPathsForSelectedItems ?? []).compactMap {
        dataSource?.itemIdentifier(for: $0)
      }
    }

    private func writeSelection() {
      guard !isApplyingUpdate, let renderer else { return }
      let ids = selectedItemIDs
      reveal.userSelected(Set(ids))
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

    // MARK: Keyboard focus

    private func takeFocusBack() {
      Task { @MainActor [weak self] in
        // This is an explicit commit with Return, so take the focus even if SwiftUI has not yet
        // removed the text field. Ordinary row selection must leave an active text field alone.
        guard let self, let id = self.keyboardItemID,
          let indexPath = self.dataSource?.indexPath(for: id)
        else { return }
        self.updateNativeFocus(at: indexPath, takingKeyboardFocus: true, afterRenaming: true)
      }
    }

    private func canSelect(_ id: ID) -> Bool {
      guard let renderer else { return false }
      if case .none = renderer.selection { return false }
      return renderer.behavior.canSelect(id, in: tree)
    }

    private var keyboardItemID: ID? {
      if let focusedItemID, tree.contains(focusedItemID), displayedRowsContain(focusedItemID) {
        return focusedItemID
      }
      return selectedItemIDs.first { displayedRowsContain($0) }
    }

    func canHandleKeyboardAction(_ action: OutlineKeyboardAction) -> Bool {
      if action == .previous || action == .next {
        return tree.visibleRows(expanded: displayedExpansion).contains {
          canSelect($0.id) || !tree.children(of: $0.id).isEmpty
        }
      }
      guard let id = keyboardItemID else { return false }
      switch action {
      case .previous, .next:
        return true
      case .expand:
        return !tree.children(of: id).isEmpty
      case .collapse:
        return !tree.children(of: id).isEmpty || tree.parent(of: id) != nil
      case .toggle:
        return !tree.children(of: id).isEmpty || renderer?.behavior.primaryAction != nil
      case .activate:
        return renderer?.behavior.primaryAction != nil
          || (!canSelect(id) && !tree.children(of: id).isEmpty)
      }
    }

    /// Horizontal arrows navigate the hierarchy; Return activates and Space toggles containers.
    func handleKeyboardAction(_ action: OutlineKeyboardAction) {
      guard canHandleKeyboardAction(action) else { return }
      if keyboardItemID == nil, action == .previous || action == .next {
        let candidates = tree.visibleRows(expanded: displayedExpansion).filter {
          canSelect($0.id) || !tree.children(of: $0.id).isEmpty
        }
        if let row = action == .next ? candidates.first : candidates.last { focus(row.id) }
        return
      }
      guard let id = keyboardItemID else { return }
      let children = tree.children(of: id)
      switch action {
      case .previous, .next:
        let rows = tree.visibleRows(expanded: displayedExpansion)
        guard let index = rows.firstIndex(where: { $0.id == id }) else { return }
        let step = action == .next ? 1 : -1
        var next = index + step
        while rows.indices.contains(next) {
          let candidate = rows[next].id
          if canSelect(candidate) || !tree.children(of: candidate).isEmpty {
            focus(candidate)
            return
          }
          next += step
        }
      case .expand:
        if displayedExpansion.contains(id) {
          if let child = children.first { focus(child) }
        } else {
          userChangedExpansion(of: id, expanded: true)
        }
      case .collapse:
        if displayedExpansion.contains(id), !children.isEmpty {
          userChangedExpansion(of: id, expanded: false)
        } else if let parent = tree.parent(of: id) {
          focus(parent)
        }
      case .toggle:
        if !children.isEmpty { toggle(id) } else { activate(id) }
      case .activate:
        if !canSelect(id), !children.isEmpty { toggle(id) } else { activate(id) }
      }
    }

    private func activate(_ id: ID) {
      renderer?.behavior.primaryAction?(activatedIDs(for: id))
    }

    private func focus(_ id: ID) {
      guard let collectionView, let indexPath = dataSource?.indexPath(for: id) else { return }
      focusedItemID = id
      if canSelect(id) {
        applySelection([id])
        writeSelection()
      }
      collectionView.scrollToItem(at: indexPath, at: .centeredVertically, animated: false)
      updateNativeFocus(at: indexPath)
    }

    private func updateNativeFocus(
      at indexPath: IndexPath, takingKeyboardFocus: Bool = false, afterRenaming: Bool = false
    ) {
      guard let collectionView = collectionView as? SnagCollectionView else { return }
      collectionView.layoutIfNeeded()
      // Set the preferred cell before becoming first responder, otherwise UIKit can focus its
      // remembered row and overwrite the row the user just touched or renamed.
      collectionView.keyboardFocusTarget = collectionView.cellForItem(at: indexPath)
      defer { collectionView.keyboardFocusTarget = nil }
      if takingKeyboardFocus {
        if afterRenaming {
          collectionView.becomeFirstResponder()
        } else if !collectionView.takeKeyboardFocus() {
          return
        }
      }
      let focusSystem = UIFocusSystem(for: collectionView)
      focusSystem?.requestFocusUpdate(to: collectionView)
      focusSystem?.updateFocusIfNeeded()
    }

    func collectionView(
      _ collectionView: UICollectionView, canFocusItemAt indexPath: IndexPath
    ) -> Bool {
      guard let id = dataSource?.itemIdentifier(for: indexPath) else { return false }
      return canSelect(id) || !tree.children(of: id).isEmpty
    }

    func collectionView(
      _ collectionView: UICollectionView, selectionFollowsFocusForItemAt indexPath: IndexPath
    ) -> Bool {
      guard let id = dataSource?.itemIdentifier(for: indexPath) else { return false }
      return canSelect(id)
    }

    func collectionView(
      _ collectionView: UICollectionView,
      didUpdateFocusIn context: UICollectionViewFocusUpdateContext,
      with coordinator: UIFocusAnimationCoordinator
    ) {
      // Hosted content can briefly own native focus without an index path. Retain the logical
      // outline position, including headers which deliberately have no selected index path.
      if let id = context.nextFocusedIndexPath.flatMap({ dataSource?.itemIdentifier(for: $0) }) {
        focusedItemID = id
      }
    }

    // MARK: Dragging

    /// How a row shows that a drop would land on or next to it.
    enum DropIndicator: Equatable {
      /// The drop lands onto the row.
      case onto(ID)
      /// The drop is inserted at the top or bottom edge of the row, at the given nesting depth.
      case line(ID, atBottom: Bool, depth: Int)
    }

    /// The private type that marks rows dragged from this outline.
    ///
    /// Unique per outline, so drops can recognize their own drags synchronously. Visible only
    /// within this process, it needs no declaration in the app's Info.plist and never leaves the
    /// app.
    private let draggedRowType = "io.github.kerker00.gmsnagnav.outline-row.\(UUID().uuidString)"

    /// The elements of the drag that is in progress, recorded when it begins.
    private var currentDragIDs: [ID] = []

    /// The frames of the visible rows when the drag entered the list, in display order.
    ///
    /// While the user drags, UIKit moves cells aside to preview an insertion — the dragged row's
    /// placeholder then sits under the finger. Hit-testing that moving layout would keep finding
    /// the dragged row itself, so drops are located against the frames from before the preview.
    private var dragRowFrames: [CGRect]?

    /// Where the current drop would land, drawn by the rows themselves.
    ///
    /// UIKit's own feedback moves cells aside to open a gap, so the row under the finger slides
    /// away and the target flips back and forth. The rows stay in place instead, and draw either a
    /// highlight (onto the row) or an insertion line at one edge, indented to the target level.
    private var dropIndicator: DropIndicator? {
      didSet {
        if dropIndicator != oldValue { refreshVisibleCells() }
      }
    }

    /// The host's answers for the current drag and snapshot.
    private var dropCache = DropResolutionCache<ID>()
    /// Where the elements would land if the user lifted the finger now, before the host's answer.
    private var pendingTarget: OutlineDropTarget<ID>?

    /// Starts a drag from the row of `id`, called by the row's hosted content.
    ///
    /// Rows drag through SwiftUI, from the same view as their context menu, so a long press shows
    /// the menu and moving the finger lifts the row out of it — like the Files app. A row that
    /// belongs to a multiple selection drags the whole selection.
    func beginDrag(from id: ID) -> NSItemProvider {
      var ids = [id]
      if let renderer, case .multiple(let binding) = renderer.selection,
        binding.wrappedValue.contains(id), let canDrag = renderer.behavior.canDrag
      {
        ids = tree.visibleRows(expanded: displayedExpansion).map(\.id).filter { row in
          binding.wrappedValue.contains(row) && tree.element(row).map(canDrag) == true
        }
      }
      currentDragIDs = ids
      return dragItemProvider()
    }

    /// An item provider marked with this outline's private type.
    private func dragItemProvider() -> NSItemProvider {
      // iOS offers a drag to drop targets only if it carries at least one type.
      let provider = NSItemProvider()
      provider.registerDataRepresentation(
        forTypeIdentifier: draggedRowType, visibility: .ownProcess
      ) { completion in
        completion(Data(), nil)
        return nil
      }
      return provider
    }

    func collectionView(
      _ collectionView: UICollectionView, itemsForBeginning session: UIDragSession,
      at indexPath: IndexPath
    ) -> [UIDragItem] {
      guard let id = draggableID(at: indexPath) else { return [] }
      return [UIDragItem(itemProvider: beginDrag(from: id))]
    }

    func collectionView(
      _ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession,
      at indexPath: IndexPath, point: CGPoint
    ) -> [UIDragItem] {
      guard let id = draggableID(at: indexPath), !currentDragIDs.contains(id) else { return [] }
      currentDragIDs.append(id)
      return [UIDragItem(itemProvider: dragItemProvider())]
    }

    private func draggableID(at indexPath: IndexPath) -> ID? {
      guard let canDrag = renderer?.behavior.canDrag,
        let id = dataSource?.itemIdentifier(for: indexPath),
        let element = tree.element(id), canDrag(element)
      else { return nil }
      return id
    }

    /// The elements of this outline being dragged in `session`, in order.
    private func draggedIDs(in session: UIDropSession) -> [ID] {
      guard session.localDragSession != nil,
        session.hasItemsConforming(toTypeIdentifiers: [draggedRowType])
      else { return [] }
      return currentDragIDs
    }

    /// Where a drop lands: *onto* a row while the finger rests on its middle half, otherwise
    /// *between* rows, resolved with the gap rule of `dropTarget(forGap:in:)`. The empty space
    /// below the last row inserts at the end of the root level, like a drop there on macOS.
    ///
    /// - Parameters:
    ///   - row: The visible row under the finger, if any.
    ///   - verticalFraction: Where the finger is within that row, from `0` (top) to `1` (bottom).
    ///   - rows: The visible rows.
    func dropTarget(
      over row: Int?, verticalFraction: CGFloat, in rows: [VisibleRow<ID>]
    ) -> OutlineDropTarget<ID> {
      guard let row, rows.indices.contains(row) else {
        return .insert(into: nil, at: tree.roots.count)
      }
      if (0.25...0.75).contains(verticalFraction) {
        return .onto(rows[row].id)
      }
      return tree.dropTarget(forGap: verticalFraction < 0.25 ? row : row + 1, in: rows)
    }

    func collectionView(
      _ collectionView: UICollectionView, canHandle session: UIDropSession
    ) -> Bool {
      !draggedIDs(in: session).isEmpty
    }

    func collectionView(
      _ collectionView: UICollectionView, dropSessionDidUpdate session: UIDropSession,
      withDestinationIndexPath destinationIndexPath: IndexPath?
    ) -> UICollectionViewDropProposal {
      pendingTarget = nil
      guard renderer?.behavior.drop != nil else {
        return UICollectionViewDropProposal(operation: .forbidden)
      }
      let location = session.location(in: collectionView)
      let rows = tree.visibleRows(expanded: displayedExpansion)
      let frames = dragRowFrames ?? captureRowFrames(count: rows.count)
      let hit = Self.row(at: location.y, in: frames)
      let target = dropTarget(over: hit.row, verticalFraction: hit.fraction, in: rows)
      updateSpringLoading(for: target)

      guard let resolved = resolveDrop(of: draggedIDs(in: session), at: target) else {
        dropIndicator = nil
        return UICollectionViewDropProposal(operation: .forbidden)
      }
      pendingTarget = target
      dropIndicator = indicator(for: resolved.proposal.target, near: hit, in: rows)

      let operation: UIDropOperation = resolved.operation == .copy ? .copy : .move
      // `.unspecified` keeps UIKit from moving cells aside; the rows draw the feedback.
      return UICollectionViewDropProposal(operation: operation, intent: .unspecified)
    }

    func collectionView(
      _ collectionView: UICollectionView,
      performDropWith coordinator: UICollectionViewDropCoordinator
    ) {
      dropIndicator = nil
      guard let target = pendingTarget else { return }
      pendingTarget = nil
      // The host changes its data; the next update animates the rows to their new place.
      _ = performDrop(of: currentDragIDs, at: target)
    }

    /// Asks the host whether and where `ids` may be dropped at `target`, reusing its answer until
    /// the data changes.
    func resolveDrop(
      of ids: [ID], at target: OutlineDropTarget<ID>
    ) -> (proposal: OutlineDropProposal<ID>, operation: OutlineDropOperation)? {
      guard let renderer, let drop = renderer.behavior.drop, !ids.isEmpty else { return nil }
      return dropCache.resolution(for: ids, target: target) {
        drop.resolve(draggedIDs: ids, target: target, tree: tree, expanded: renderer.expansion)
      }
    }

    /// Lets the host perform a drop and returns whether it did.
    ///
    /// The drop is resolved again, because the host's data may have changed since the finger last
    /// moved; a proposal from before that change could carry outdated positions.
    func performDrop(of ids: [ID], at target: OutlineDropTarget<ID>) -> Bool {
      guard let drop = renderer?.behavior.drop, let resolved = resolveDrop(of: ids, at: target)
      else { return false }
      return drop.perform(resolved.proposal, resolved.operation)
    }

    func collectionView(
      _ collectionView: UICollectionView, dropSessionDidEnter session: UIDropSession
    ) {
      dragRowFrames = nil
    }

    func collectionView(
      _ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession
    ) {
      dropIndicator = nil
    }

    func collectionView(
      _ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession
    ) {
      pendingTarget = nil
      dragRowFrames = nil
      dropIndicator = nil
      currentDragIDs = []
      dropCache.removeAll()
      endSpringLoading()
    }

    // MARK: Spring-loading

    /// Collapsed elements opened temporarily by resting on them during the current drag.
    private(set) var springLoaded: [ID] = []
    /// The element the finger rests on, and the pending task that opens it.
    private var springLoadCandidate: ID?
    private var springLoadTask: Task<Void, Never>?
    /// Finishes once the pending spring-loading has opened its element or was cancelled, for tests.
    func springLoadingSettled() async {
      await springLoadTask?.value
    }
    /// Replaces the spring-loading delay, for tests.
    var springLoadingDelayOverride: Duration?

    private var springLoadingDelay: Duration? {
      guard let renderer, renderer.springLoading != .disabled else { return nil }
      return springLoadingDelayOverride ?? .milliseconds(600)
    }

    /// Opens collapsed elements the finger rests on and closes the ones it has left.
    func updateSpringLoading(for target: OutlineDropTarget<ID>) {
      let toClose = tree.springLoadedToClose(springLoaded, targetParent: target.parent)
      if !toClose.isEmpty {
        springLoaded.removeAll { toClose.contains($0) }
        applySpringLoadedExpansion()
      }

      var candidate: ID?
      if target.childIndex == nil, let id = target.parent, !tree.children(of: id).isEmpty,
        !displayedExpansion.contains(id)
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
        self.springLoadCandidate = nil
        self.springLoaded.append(candidate)
        self.applySpringLoadedExpansion()
      }
    }

    /// Closes what spring-loading opened, unless the host expanded it in the meantime — for
    /// example to reveal the elements just dropped into it.
    func endSpringLoading() {
      springLoadTask?.cancel()
      springLoadTask = nil
      springLoadCandidate = nil
      guard !springLoaded.isEmpty else { return }
      springLoaded.removeAll()
      applySpringLoadedExpansion()
    }

    /// Shows the current expansion; the row frames recorded for the drag are captured anew.
    private func applySpringLoadedExpansion() {
      guard let dataSource else { return }
      dataSource.apply(
        sectionSnapshot(expanded: displayedExpansion), to: 0, animatingDifferences: true)
      dragRowFrames = nil
      refreshVisibleCells()
    }

    /// The feedback for a resolved drop target, next to the row under the finger.
    ///
    /// Insertions are drawn as a line at the edge of a row adjacent to the insertion point: below
    /// the row above it, or above the first row when inserting at the very top.
    func indicator(
      for target: OutlineDropTarget<ID>, near hit: (row: Int?, fraction: CGFloat),
      in rows: [VisibleRow<ID>]
    ) -> DropIndicator? {
      guard let childIndex = target.childIndex else {
        return target.parent.map(DropIndicator.onto)
      }
      let depth = target.parent.map(childIndentationDepth) ?? 0
      let siblings = tree.children(of: target.parent)
      if childIndex > 0, siblings.indices.contains(childIndex - 1) {
        // Below the previous sibling — or below the last visible row of its expanded subtree.
        let previous = siblings[childIndex - 1]
        let lastVisible = rows.last { row in
          row.id == previous || tree.isDescendant(row.id, of: previous)
        }
        return lastVisible.map { .line($0.id, atBottom: true, depth: depth) }
      }
      if let first = siblings.first {
        return .line(first, atBottom: false, depth: depth)
      }
      // Inserting into an empty, expanded parent: below the parent row itself.
      return target.parent.map { .line($0, atBottom: true, depth: depth) }
    }

    /// The indentation of the children of `parent`: one level deeper, except below a section
    /// header, whose entries are not indented.
    private func childIndentationDepth(of parent: ID) -> Int {
      guard let behavior = renderer?.behavior else { return 0 }
      if behavior.sectionTitle(of: parent, in: tree) != nil { return 0 }
      return behavior.indentationDepth(of: parent, in: tree) + 1
    }

    /// Records the frames of the first `count` rows before UIKit starts previewing insertions.
    private func captureRowFrames(count: Int) -> [CGRect] {
      guard let collectionView else { return [] }
      let frames = (0..<count).map { item in
        collectionView.layoutAttributesForItem(at: IndexPath(item: item, section: 0))?.frame
          ?? .zero
      }
      dragRowFrames = frames
      return frames
    }

    /// The row whose frame contains `y`, and where within it `y` lies, from `0` to `1`.
    ///
    /// Above the first row the result is the first row's top edge; below the last row there is no
    /// row, which appends at the end.
    static func row(at y: CGFloat, in frames: [CGRect]) -> (row: Int?, fraction: CGFloat) {
      if let first = frames.first, y < first.minY { return (0, 0) }
      for (index, frame) in frames.enumerated() where frame.height > 0 && frame.maxY > y {
        return (index, (y - frame.minY) / frame.height)
      }
      return (nil, 0.5)
    }

    /// The elements an action on `id` applies to: the selection if `id` is part of it, otherwise
    /// `id` alone.
    func activatedIDs(for id: ID) -> Set<ID> {
      guard let renderer else { return [id] }
      let selected = selectedIDs(in: renderer.selection)
      return selected.contains(id) ? selected : [id]
    }

    // MARK: Native context menu

    func collectionView(
      _ collectionView: UICollectionView,
      contextMenuConfigurationForItemsAt indexPaths: [IndexPath], point: CGPoint
    ) -> UIContextMenuConfiguration? {
      guard let renderer, let menuItems = renderer.behavior.contextMenuItems else { return nil }
      let ids: Set<ID>
      if let first = indexPaths.first, let id = dataSource?.itemIdentifier(for: first) {
        ids = activatedIDs(for: id)
      } else {
        // Empty space: only outlines with selection offer a menu there, as on macOS.
        if case .none = renderer.selection { return nil }
        ids = []
      }
      let items = menuItems(ids)
      guard !items.isEmpty else { return nil }
      return UIContextMenuConfiguration(actionProvider: { _ in
        UIMenu(children: Self.menuElements(for: items))
      })
    }

    // MARK: Swipe actions

    /// The host's swipe actions for a row at one edge, or `nil` for no swipe.
    func swipeActionsConfiguration(
      at indexPath: IndexPath, edge: HorizontalEdge
    ) -> UISwipeActionsConfiguration? {
      let swipe =
        switch edge {
        case .leading: renderer?.behavior.leadingSwipeActions
        case .trailing: renderer?.behavior.trailingSwipeActions
        }
      guard let swipe, let id = dataSource?.itemIdentifier(for: indexPath) else { return nil }
      let actions = swipe.actions(id).compactMap(Self.contextualAction(for:))
      guard !actions.isEmpty else { return nil }
      let configuration = UISwipeActionsConfiguration(actions: actions)
      configuration.performsFirstActionWithFullSwipe = swipe.allowsFullSwipe
      return configuration
    }

    /// A swipe action for a menu action; `nil` for submenus, dividers and disabled actions,
    /// which swiping has no place for.
    static func contextualAction(for item: OutlineMenuItem) -> UIContextualAction? {
      guard case .action(let perform) = item.kind, !item.isDisabled else { return nil }
      let action = UIContextualAction(
        style: item.isDestructive ? .destructive : .normal, title: item.title
      ) { _, _, completion in
        MainActor.assumeIsolated { perform() }
        completion(true)
      }
      action.image = item.systemImage.flatMap { UIImage(systemName: $0) }
      return action
    }

    /// Converts menu items to UIKit menu elements; dividers start inline sections.
    static func menuElements(for items: [OutlineMenuItem]) -> [UIMenuElement] {
      var sections: [[UIMenuElement]] = [[]]
      for item in items {
        let image = item.systemImage.flatMap { UIImage(systemName: $0) }
        switch item.kind {
        case .divider:
          sections.append([])
        case .menu(let children):
          sections[sections.count - 1].append(
            UIMenu(title: item.title, image: image, children: menuElements(for: children)))
        case .action(let perform):
          var attributes: UIMenuElement.Attributes = []
          if item.isDestructive { attributes.insert(.destructive) }
          if item.isDisabled { attributes.insert(.disabled) }
          sections[sections.count - 1].append(
            UIAction(title: item.title, image: image, attributes: attributes) { _ in
              MainActor.assumeIsolated { perform() }
            })
        }
      }
      let nonEmpty = sections.filter { !$0.isEmpty }
      guard nonEmpty.count > 1 else { return nonEmpty.first ?? [] }
      return nonEmpty.map { UIMenu(options: .displayInline, children: $0) }
    }

    // MARK: UICollectionViewDelegate

    func collectionView(
      _ collectionView: UICollectionView, performPrimaryActionForItemAt indexPath: IndexPath
    ) {
      guard let primaryAction = renderer?.behavior.primaryAction,
        let id = dataSource?.itemIdentifier(for: indexPath)
      else { return }
      primaryAction(activatedIDs(for: id))
    }

    func collectionView(
      _ collectionView: UICollectionView, shouldSelectItemAt indexPath: IndexPath
    ) -> Bool {
      guard let id = dataSource?.itemIdentifier(for: indexPath) else { return false }
      return canSelect(id)
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
      focusedItemID = dataSource?.itemIdentifier(for: indexPath)
      writeSelection()
      updateNativeFocus(at: indexPath, takingKeyboardFocus: true)
    }

    func collectionView(
      _ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath
    ) {
      writeSelection()
    }
  }

  /// The line that marks where dragged rows would be inserted, like `NSOutlineView`'s indicator.
  private struct InsertionLine: View {
    let indent: CGFloat

    var body: some View {
      HStack(spacing: 0) {
        Circle().strokeBorder(.tint, lineWidth: 2).frame(width: 8, height: 8)
        Rectangle().fill(.tint).frame(height: 2)
      }
      .padding(.leading, indent)
      .allowsHitTesting(false)
    }
  }

  /// Lets a hosted row be dragged; the drag starts from the same view as the row's context menu.
  private struct RowDrag: ViewModifier {
    let begin: (() -> NSItemProvider?)?

    func body(content: Content) -> some View {
      if let begin {
        content.onDrag { begin() ?? NSItemProvider() }
      } else {
        content
      }
    }
  }

  /// Attaches the host's context menu to a hosted row.
  private struct RowMenu: ViewModifier {
    let menu: (() -> AnyView)?

    func body(content: Content) -> some View {
      if let menu {
        content.contextMenu { menu() }
      } else {
        content
      }
    }
  }
#endif
