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
      var primaryAction: ((Set<String>) -> Void)?
      var springLoading = SpringLoadingBehavior.automatic
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
      behavior.primaryAction = host.primaryAction
      coordinator.update(
        with: UIKitOutlineRenderer(
          tree: OutlineTree(host.roots, children: \.children),
          selection: .single(Binding(get: { host.single }, set: { host.single = $0 })),
          expansion: Binding(get: { host.expansion }, set: { host.expansion = $0 }),
          behavior: behavior,
          appearance: OutlineAppearance(),
          springLoading: host.springLoading,
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

    @Test func actsOnTheSelectionWhenTheActivatedRowBelongsToIt() {
      host.single = "c"
      update()
      #expect(coordinator.activatedIDs(for: "c") == ["c"])
      #expect(coordinator.activatedIDs(for: "a") == ["a"])
    }

    @Test func runsThePrimaryActionForTheTappedRow() {
      var activated: Set<String>?
      host.primaryAction = { activated = $0 }
      update()
      coordinator.collectionView(
        collectionView, performPrimaryActionForItemAt: IndexPath(item: 1, section: 0))
      #expect(activated == ["b"])
    }

    @Test func dropsOntoARowWhileTheFingerRestsOnItsMiddle() {
      update()
      let rows = OutlineTree(sampleRoots, children: \.children).visibleRows(expanded: [])
      #expect(coordinator.dropTarget(over: 0, verticalFraction: 0.5, in: rows) == .onto("a"))
      #expect(coordinator.dropTarget(over: 1, verticalFraction: 0.3, in: rows) == .onto("b"))
    }

    @Test func dropsBetweenRowsNearTheirEdges() {
      update()
      let rows = OutlineTree(sampleRoots, children: \.children).visibleRows(expanded: [])
      // Rows: a, b, c. The top edge of b is the gap after a; the bottom edge the gap after b.
      #expect(
        coordinator.dropTarget(over: 1, verticalFraction: 0.1, in: rows)
          == .insert(into: nil, at: 1))
      #expect(
        coordinator.dropTarget(over: 1, verticalFraction: 0.9, in: rows)
          == .insert(into: nil, at: 2))
    }

    @Test func appendsBelowTheLastRow() {
      update()
      let rows = OutlineTree(sampleRoots, children: \.children).visibleRows(expanded: [])
      #expect(
        coordinator.dropTarget(over: nil, verticalFraction: 0.5, in: rows)
          == .insert(into: nil, at: 3))
    }

    @Test func locatesTheFingerAgainstRecordedRowFrames() {
      typealias Coordinator = UIKitOutlineCoordinator<TestItem, Text>
      let frames = [
        CGRect(x: 0, y: 0, width: 300, height: 40), CGRect(x: 0, y: 40, width: 300, height: 40),
      ]
      #expect(Coordinator.row(at: 10, in: frames).row == 0)
      #expect(Coordinator.row(at: 10, in: frames).fraction == 0.25)
      #expect(Coordinator.row(at: 60, in: frames).row == 1)
      #expect(Coordinator.row(at: 60, in: frames).fraction == 0.5)
      // Above the first row counts as its top edge; below the last row there is no row.
      #expect(Coordinator.row(at: -5, in: frames).row == 0)
      #expect(Coordinator.row(at: -5, in: frames).fraction == 0)
      #expect(Coordinator.row(at: 100, in: frames).row == nil)
    }

    private func restOn(_ target: OutlineDropTarget<String>) async {
      coordinator.updateSpringLoading(for: target)
      try? await Task.sleep(for: .milliseconds(250))
    }

    @Test func springLoadsCollapsedFoldersWithoutChangingTheBinding() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      update()
      await restOn(.onto("a"))
      #expect(coordinator.springLoaded == ["a"])
      #expect(coordinator.displayedExpansion.contains("a"))
      #expect(host.expansion.isEmpty)

      // Resting inside the opened folder keeps it open and opens the next level.
      await restOn(.onto("a2"))
      #expect(coordinator.springLoaded == ["a", "a2"])
    }

    @Test func closesSpringLoadedFoldersWhenTheFingerLeaves() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      update()
      await restOn(.onto("a"))
      await restOn(.insert(into: nil, at: 3))
      #expect(coordinator.springLoaded.isEmpty)
      #expect(!coordinator.displayedExpansion.contains("a"))
    }

    @Test func keepsFoldersTheHostExpandedWhenTheDragEnds() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      update()
      await restOn(.onto("a"))
      await restOn(.onto("a2"))
      host.expansion.insert("a")
      coordinator.endSpringLoading()
      #expect(coordinator.displayedExpansion == ["a"])
    }

    @Test func doesNotSpringLoadWhenDisabled() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      host.springLoading = .disabled
      update()
      await restOn(.onto("a"))
      #expect(coordinator.springLoaded.isEmpty)
    }

    @Test func ignoresLeavesAndEmptyFolders() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      update()
      await restOn(.onto("b"))
      await restOn(.onto("c"))
      #expect(coordinator.springLoaded.isEmpty)
    }

    @Test func indicatesDropsOntoRowsWithAHighlight() {
      update()
      let rows = OutlineTree(sampleRoots, children: \.children).visibleRows(expanded: [])
      #expect(coordinator.indicator(for: .onto("a"), near: (0, 0.5), in: rows) == .onto("a"))
    }

    @Test func drawsInsertionLinesBelowThePreviousSibling() {
      host.expansion = ["a"]
      update()
      let rows = OutlineTree(sampleRoots, children: \.children).visibleRows(expanded: ["a"])
      // Rows: a, a1, a2, b, c. Inserting at root index 1 goes below a's last visible row, a2.
      #expect(
        coordinator.indicator(for: .insert(into: nil, at: 1), near: (3, 0.1), in: rows)
          == .line("a2", atBottom: true, depth: 0))
      // Inserting into a at index 1 goes below a1, one level deep.
      #expect(
        coordinator.indicator(for: .insert(into: "a", at: 1), near: (1, 0.9), in: rows)
          == .line("a1", atBottom: true, depth: 1))
    }

    @Test func drawsInsertionLinesAboveTheFirstChild() {
      host.expansion = ["a"]
      update()
      let rows = OutlineTree(sampleRoots, children: \.children).visibleRows(expanded: ["a"])
      #expect(
        coordinator.indicator(for: .insert(into: nil, at: 0), near: (0, 0.1), in: rows)
          == .line("a", atBottom: false, depth: 0))
      #expect(
        coordinator.indicator(for: .insert(into: "a", at: 0), near: (1, 0.1), in: rows)
          == .line("a1", atBottom: false, depth: 1))
    }
  }
#endif
