#if os(iOS)
  import SwiftUI
  import Testing
  import UIKit

  @testable import GMSnagNav

  /// Drives the UIKit coordinator with a real, window-less `UICollectionView`.
  @MainActor
  @Suite struct UIKitOutlineCoordinatorTests {
    final class Host {
      var roots = sampleRoots
      var expansion: Set<String> = []
      var single: String?
      var isSelectable: (TestItem) -> Bool = { _ in true }
    }

    let host = Host()
    let coordinator = UIKitOutlineCoordinator<TestItem, Text>()
    let collectionView = UICollectionView(
      frame: CGRect(x: 0, y: 0, width: 320, height: 640),
      collectionViewLayout: UIKitOutlineCoordinator<TestItem, Text>.layout(for: .sidebar))

    init() {
      coordinator.attach(to: collectionView)
    }

    private func update() {
      let host = host
      var behavior = OutlineBehavior<TestItem>()
      behavior.isSelectable = host.isSelectable
      coordinator.update(
        with: UIKitOutlineRenderer(
          tree: OutlineTree(host.roots, children: \.children),
          selection: .single(Binding(get: { host.single }, set: { host.single = $0 })),
          expansion: Binding(get: { host.expansion }, set: { host.expansion = $0 }),
          behavior: behavior,
          appearance: OutlineAppearance(),
          rowContent: { Text($0.id) }))
    }

    @Test func buildsTheWholeTreeAndShowsExpandedLevels() {
      host.expansion = ["a", "a2"]
      update()
      let snapshot = coordinator.sectionSnapshot(expanded: host.expansion)
      #expect(snapshot.items == ["a", "a1", "a2", "a2x", "b", "c"])
      #expect(snapshot.visibleItems == ["a", "a1", "a2", "a2x", "b", "c"])
      #expect(snapshot.level(of: "a2x") == 2)
    }

    @Test func hidesChildrenOfCollapsedItems() {
      host.expansion = ["a2"]
      update()
      let snapshot = coordinator.sectionSnapshot(expanded: host.expansion)
      #expect(snapshot.visibleItems == ["a", "b", "c"])
    }

    @Test func ignoresExpansionOfLeavesAndEmptyContainers() {
      update()
      let snapshot = coordinator.sectionSnapshot(expanded: ["b", "c", "missing"])
      #expect(!snapshot.isExpanded("b"))
      #expect(!snapshot.isExpanded("c"))
    }

    @Test func appliesSelectionFromTheBinding() {
      host.single = "c"
      update()
      #expect(coordinator.selectedItemIDs == ["c"])

      host.single = nil
      update()
      #expect(coordinator.selectedItemIDs.isEmpty)
    }

    @Test func refusesToSelectUnselectableItems() {
      host.isSelectable = { $0.children == nil }
      update()
      #expect(
        !coordinator.collectionView(
          collectionView, shouldSelectItemAt: IndexPath(item: 0, section: 0)))
      #expect(
        coordinator.collectionView(
          collectionView, shouldSelectItemAt: IndexPath(item: 2, section: 0)))
    }

    @Test func writesUserSelectionIntoTheBinding() {
      update()
      collectionView.selectItem(
        at: IndexPath(item: 2, section: 0), animated: false, scrollPosition: [])
      coordinator.collectionView(collectionView, didSelectItemAt: IndexPath(item: 2, section: 0))
      #expect(host.single == "c")
    }
  }
#endif
