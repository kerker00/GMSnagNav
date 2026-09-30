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
    let rowContent: (Element) -> RowContent

    func makeCoordinator() -> UIKitOutlineCoordinator<Element, RowContent> {
      UIKitOutlineCoordinator()
    }

    func makeUIView(context: Context) -> UICollectionView {
      let collectionView = UICollectionView(
        frame: .zero,
        collectionViewLayout: UIKitOutlineCoordinator<Element, RowContent>.layout(
          for: appearance.style))
      collectionView.backgroundColor = .clear
      context.coordinator.attach(to: collectionView)
      context.coordinator.update(with: self)
      return collectionView
    }

    func updateUIView(_ collectionView: UICollectionView, context: Context) {
      context.coordinator.update(with: self)
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

    static func layout(for style: SnagOutlineStyle) -> UICollectionViewCompositionalLayout {
      let appearance: UICollectionLayoutListConfiguration.Appearance =
        switch style {
        case .automatic, .sidebar: .sidebar
        case .plain: .plain
        }
      var configuration = UICollectionLayoutListConfiguration(appearance: appearance)
      configuration.backgroundColor = .clear
      return UICollectionViewCompositionalLayout.list(using: configuration)
    }

    /// Connects the coordinator to a collection view as its data source owner and delegate.
    func attach(to collectionView: UICollectionView) {
      self.collectionView = collectionView
      collectionView.delegate = self
      collectionView.dragDelegate = self
      collectionView.dropDelegate = self

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
    func update(with renderer: Renderer) {
      self.renderer = renderer
      tree = renderer.tree
      guard let collectionView, let dataSource else { return }

      isApplyingUpdate = true
      defer { isApplyingUpdate = false }

      if appliedStyle != renderer.appearance.style {
        if appliedStyle != nil {
          collectionView.setCollectionViewLayout(
            Self.layout(for: renderer.appearance.style), animated: false)
        }
        appliedStyle = renderer.appearance.style
      }
      switch renderer.selection {
      case .none, .single: collectionView.allowsMultipleSelection = false
      case .multiple: collectionView.allowsMultipleSelection = true
      }
      // Off by default on iPhone.
      collectionView.dragInteractionEnabled = renderer.behavior.canDrag != nil

      dataSource.apply(
        sectionSnapshot(expanded: renderer.expansion), to: 0, animatingDifferences: hasLoaded)
      hasLoaded = true
      refreshVisibleCells()
      applySelection(selectedIDs(in: renderer.selection))
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

    /// The element each cell currently shows, keyed by the cell's identity.
    private var cellElements: [ObjectIdentifier: ID] = [:]

    private func configure(_ cell: UICollectionViewListCell, for id: ID) {
      cellElements[ObjectIdentifier(cell)] = id
      guard let renderer, let element = tree.element(id), let node = tree.node(id) else { return }
      let children = node.children ?? []
      let row = VisibleRow(
        id: id, depth: node.depth, parent: node.parent, index: node.index,
        isExpandable: node.children != nil,
        isExpanded: !children.isEmpty && renderer.expansion.contains(id),
        childCount: children.count)
      // The row draws its own leading chevron and indentation: UIKit places its outline
      // disclosure on the trailing edge of sidebar lists and does not indent hosted content.
      let menu = renderer.behavior.contextMenu
      let menuIDs = activatedIDs(for: id)
      let isDropTarget = highlightedDropTarget == id
      cell.contentConfiguration = UIHostingConfiguration {
        OutlineRowView(
          row: row, indentation: renderer.appearance.indentation, isExpanded: row.isExpanded,
          toggle: { [weak self] in self?.toggle(id) }, content: renderer.rowContent(element)
        )
        .modifier(RowMenu(menu: menu.map { menu in { menu(menuIDs) } }))
        .background {
          if isDropTarget {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
              .fill(.tint.opacity(0.25))
              .padding(.horizontal, -8)
          }
        }
      }
      .margins(.vertical, 6)
      cell.indentationLevel = 0
      cell.accessories = []
    }

    /// Expands or collapses an item on the user's behalf.
    private func toggle(_ id: ID) {
      guard let renderer, !tree.children(of: id).isEmpty else { return }
      userChangedExpansion(of: id, expanded: !renderer.expansion.contains(id))
    }

    // MARK: Expansion

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

    // MARK: Dragging

    /// The private type that marks rows dragged within an outline.
    static var draggedRowType: String { "io.github.kerker00.gmsnagnav.outline-row" }

    /// The dragged element, carried in-process as the drag item's local object.
    private final class DragPayload {
      let id: ID

      init(_ id: ID) {
        self.id = id
      }
    }

    /// The frames of the visible rows when the drag entered the list, in display order.
    ///
    /// While the user drags, UIKit moves cells aside to preview an insertion — the dragged row's
    /// placeholder then sits under the finger. Hit-testing that moving layout would keep finding
    /// the dragged row itself, so drops are located against the frames from before the preview.
    private var dragRowFrames: [CGRect]?

    /// The row highlighted as the target of a drop *onto* it.
    ///
    /// UIKit highlights the cell it computes itself, which — with cells moving aside for the
    /// insertion preview — is often not the row under the finger, so the row is highlighted here.
    private var highlightedDropTarget: ID? {
      didSet {
        if highlightedDropTarget != oldValue { refreshVisibleCells() }
      }
    }

    /// The last drop resolved while the user drags, performed when they lift the finger.
    private var pendingDrop: (proposal: OutlineDropProposal<ID>, operation: OutlineDropOperation)?

    func collectionView(
      _ collectionView: UICollectionView, itemsForBeginning session: UIDragSession,
      at indexPath: IndexPath
    ) -> [UIDragItem] {
      session.localContext = self
      return dragItems(at: indexPath)
    }

    func collectionView(
      _ collectionView: UICollectionView, itemsForAddingTo session: UIDragSession,
      at indexPath: IndexPath, point: CGPoint
    ) -> [UIDragItem] {
      dragItems(at: indexPath)
    }

    private func dragItems(at indexPath: IndexPath) -> [UIDragItem] {
      guard let canDrag = renderer?.behavior.canDrag,
        let id = dataSource?.itemIdentifier(for: indexPath),
        let element = tree.element(id), canDrag(element)
      else { return [] }
      // iOS offers a drag to drop targets only if it carries at least one type. A private type,
      // visible only within this process, needs no declaration in the app's Info.plist and never
      // leaves the app; the element itself travels as the local object.
      let provider = NSItemProvider()
      provider.registerDataRepresentation(
        forTypeIdentifier: Self.draggedRowType, visibility: .ownProcess
      ) { completion in
        completion(Data(), nil)
        return nil
      }
      let item = UIDragItem(itemProvider: provider)
      item.localObject = DragPayload(id)
      return [item]
    }

    /// The elements of this outline being dragged in `session`, in order.
    private func draggedIDs(in session: UIDropSession) -> [ID] {
      guard session.localDragSession?.localContext as AnyObject? === self else { return [] }
      return session.items.compactMap { ($0.localObject as? DragPayload)?.id }
    }

    /// Where a drop lands: *onto* a row while the finger rests on its middle half, otherwise
    /// *between* rows, resolved with the gap rule of `dropTarget(forGap:in:)`.
    ///
    /// - Parameters:
    ///   - row: The visible row under the finger, if any.
    ///   - verticalFraction: Where the finger is within that row, from `0` (top) to `1` (bottom).
    ///   - rows: The visible rows.
    func dropTarget(
      over row: Int?, verticalFraction: CGFloat, in rows: [VisibleRow<ID>]
    ) -> OutlineDropTarget<ID> {
      guard let row, rows.indices.contains(row) else {
        return tree.dropTarget(forGap: rows.count, in: rows)
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
      pendingDrop = nil
      guard let renderer, let drop = renderer.behavior.drop else {
        return UICollectionViewDropProposal(operation: .forbidden)
      }
      let location = session.location(in: collectionView)
      let rows = tree.visibleRows(expanded: renderer.expansion)
      let frames = dragRowFrames ?? captureRowFrames(count: rows.count)
      let hit = Self.row(at: location.y, in: frames)
      let target = dropTarget(over: hit.row, verticalFraction: hit.fraction, in: rows)

      guard
        let resolved = drop.resolve(
          draggedIDs: draggedIDs(in: session), target: target, tree: tree,
          expanded: renderer.expansion)
      else {
        highlightedDropTarget = nil
        return UICollectionViewDropProposal(operation: .forbidden)
      }
      pendingDrop = resolved

      let operation: UIDropOperation = resolved.operation == .copy ? .copy : .move
      if resolved.proposal.target.childIndex == nil {
        // Onto a row: highlight it ourselves and keep UIKit from opening a gap elsewhere.
        highlightedDropTarget = resolved.proposal.target.parent
        return UICollectionViewDropProposal(operation: operation, intent: .unspecified)
      }
      highlightedDropTarget = nil
      return UICollectionViewDropProposal(
        operation: operation, intent: .insertAtDestinationIndexPath)
    }

    func collectionView(
      _ collectionView: UICollectionView,
      performDropWith coordinator: UICollectionViewDropCoordinator
    ) {
      highlightedDropTarget = nil
      guard let drop = renderer?.behavior.drop, let pending = pendingDrop else { return }
      pendingDrop = nil
      // The host changes its data; the next update animates the rows to their new place.
      _ = drop.perform(pending.proposal, pending.operation)
    }

    func collectionView(
      _ collectionView: UICollectionView, dropSessionDidEnter session: UIDropSession
    ) {
      dragRowFrames = nil
    }

    func collectionView(
      _ collectionView: UICollectionView, dropSessionDidExit session: UIDropSession
    ) {
      highlightedDropTarget = nil
    }

    func collectionView(
      _ collectionView: UICollectionView, dropSessionDidEnd session: UIDropSession
    ) {
      pendingDrop = nil
      dragRowFrames = nil
      highlightedDropTarget = nil
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
      guard let renderer, let id = dataSource?.itemIdentifier(for: indexPath),
        let element = tree.element(id)
      else { return false }
      var canSelect = renderer.behavior.canSelect(element)
      if case .none = renderer.selection { canSelect = false }
      // Tapping a container that cannot be selected expands or collapses it instead.
      if !canSelect { toggle(id) }
      return canSelect
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
      writeSelection()
    }

    func collectionView(
      _ collectionView: UICollectionView, didDeselectItemAt indexPath: IndexPath
    ) {
      writeSelection()
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
