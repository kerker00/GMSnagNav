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
    UICollectionViewDelegate
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
    private func refreshVisibleCells() {
      guard let collectionView, let dataSource else { return }
      for indexPath in collectionView.indexPathsForVisibleItems {
        guard let id = dataSource.itemIdentifier(for: indexPath),
          let cell = collectionView.cellForItem(at: indexPath) as? UICollectionViewListCell
        else { continue }
        configure(cell, for: id)
      }
    }

    private func configure(_ cell: UICollectionViewListCell, for id: ID) {
      guard let renderer, let element = tree.element(id), let node = tree.node(id) else { return }
      let children = node.children ?? []
      let row = VisibleRow(
        id: id, depth: node.depth, parent: node.parent, index: node.index,
        isExpandable: node.children != nil,
        isExpanded: !children.isEmpty && renderer.expansion.contains(id),
        childCount: children.count)
      // The row draws its own leading chevron and indentation: UIKit places its outline
      // disclosure on the trailing edge of sidebar lists and does not indent hosted content.
      cell.contentConfiguration = UIHostingConfiguration {
        OutlineRowView(
          row: row, indentation: renderer.appearance.indentation, isExpanded: row.isExpanded,
          toggle: { [weak self] in self?.toggle(id) }, content: renderer.rowContent(element))
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

    // MARK: UICollectionViewDelegate

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
#endif
