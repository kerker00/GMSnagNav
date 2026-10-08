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
      var multiple: Set<String> = []
      var isSelectable: (TestItem) -> Bool = { _ in true }
      var primaryAction: ((Set<String>) -> Void)?
      var springLoading = SpringLoadingBehavior.automatic
      var drop: OutlineDropHandler<String>?
      var trailingSwipeActions: OutlineSwipeActions<String>?
      var sectionTitle: ((TestItem) -> String?)?
      var revealsSelection = true
      var navigation: OutlineNavigationRequest<String>?
      var navigationResults: [OutlineNavigationResult] = []
      var badge: OutlineBadge?
      var canReorder: ((TestItem) -> Bool)?
    }

    let host = Host()
    let coordinator = UIKitOutlineCoordinator<TestItem, Text>()
    let collectionView = SnagCollectionView(
      frame: CGRect(x: 0, y: 0, width: 320, height: 640),
      collectionViewLayout: UIKitOutlineCoordinator<TestItem, Text>.layout(for: .sidebar))

    init() {
      coordinator.attach(to: collectionView)
    }

    private func update(
      layoutDirection: LayoutDirection = .leftToRight, multipleSelection: Bool = false
    ) {
      let host = host
      var behavior = OutlineBehavior<TestItem>()
      behavior.isSelectable = host.isSelectable
      behavior.primaryAction = host.primaryAction
      behavior.drop = host.drop
      behavior.trailingSwipeActions = host.trailingSwipeActions
      behavior.sectionTitle = host.sectionTitle
      behavior.revealsSelection = host.revealsSelection
      behavior.navigation = OutlineNavigationHandler(
        request: Binding(get: { host.navigation }, set: { host.navigation = $0 }),
        onCompletion: { _, result in host.navigationResults.append(result) })
      behavior.badge = { _ in host.badge }
      behavior.canReorder = host.canReorder
      let selection: OutlineSelection<String> =
        multipleSelection
        ? .multiple(Binding(get: { host.multiple }, set: { host.multiple = $0 }))
        : .single(Binding(get: { host.single }, set: { host.single = $0 }))
      coordinator.update(
        with: UIKitOutlineRenderer(
          tree: OutlineTree(host.roots, children: \.children),
          selection: selection,
          expansion: Binding(get: { host.expansion }, set: { host.expansion = $0 }),
          behavior: behavior,
          appearance: OutlineAppearance(),
          springLoading: host.springLoading,
          rowContent: { Text($0.id) }),
        layoutDirection: layoutDirection)
    }

    @Test func explicitRevealOpensAncestorsAndRepeatsWithoutChangingSelection() async throws {
      let window = UIWindow(frame: collectionView.frame)
      let controller = UIViewController()
      window.rootViewController = controller
      controller.view.addSubview(collectionView)
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      host.single = "a2x"
      host.revealsSelection = false
      host.navigation = .reveal("a2x")
      update()
      await coordinator.navigationSettled()
      #expect(host.expansion == ["a", "a2"])
      #expect(try appliedSnapshot().visibleItems.contains("a2x"))
      #expect(host.single == "a2x")
      #expect(coordinator.selectedItemIDs == ["a2x"])
      #expect(host.navigationResults == [.completed])
      host.expansion = []
      update()
      host.navigation = .reveal("a2x")
      update()
      await coordinator.navigationSettled()
      #expect(host.expansion == ["a", "a2"])
      #expect(host.navigationResults == [.completed, .completed])
    }

    @Test func navigationUsesTheLatestTreeAndReportsMissingElements() async {
      host.navigation = .reveal("a2x")
      update()
      host.roots = [.leaf("c")]
      update()
      await coordinator.navigationSettled()
      #expect(host.navigationResults == [.elementNotFound])
      #expect(host.expansion.isEmpty)
      #expect(host.navigation == nil)
    }

    @Test func explicitNavigationTakesPrecedenceOverAutomaticSelectionReveal() async {
      let window = UIWindow(frame: collectionView.frame)
      let controller = UIViewController()
      window.rootViewController = controller
      controller.view.addSubview(collectionView)
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      host.single = "a2x"
      host.navigation = .reveal("b")
      update()
      await coordinator.navigationSettled()
      update()
      #expect(host.expansion.isEmpty)
      #expect(host.single == "a2x")
      #expect(host.navigationResults == [.completed])
    }

    @Test func focusRequestTransfersFromDetailAndPreservesSelection() async {
      let window = UIWindow(frame: collectionView.frame)
      let controller = UIViewController()
      window.rootViewController = controller
      controller.view.addSubview(collectionView)
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      host.single = "c"
      update()
      let field = UITextField(frame: CGRect(x: 330, y: 0, width: 200, height: 40))
      controller.view.addSubview(field)
      #expect(field.becomeFirstResponder())
      host.navigation = .focus()
      update()
      await coordinator.navigationSettled()
      #expect(collectionView.isFirstResponder)
      #expect(host.single == "c")
      #expect(coordinator.selectedItemIDs == ["c"])
      #expect(host.expansion.isEmpty)
      #expect(host.navigationResults == [.completed])
    }

    @Test func explicitRevealPreservesInlineTextInput() async {
      let window = UIWindow(frame: collectionView.frame)
      let controller = UIViewController()
      window.rootViewController = controller
      controller.view.addSubview(collectionView)
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      update()
      let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
      collectionView.addSubview(field)
      #expect(field.becomeFirstResponder())
      host.navigation = .reveal("a2x", focus: true)
      update()
      await coordinator.navigationSettled()
      #expect(field.isFirstResponder)
      #expect(host.expansion == ["a", "a2"])
      #expect(host.navigationResults == [.focusUnavailable])
    }

    @Test func detachedOutlineReportsUnavailableWithoutExpanding() async {
      host.navigation = .reveal("a2x")
      update()
      await coordinator.navigationSettled()
      #expect(host.navigationResults == [.outlineUnavailable])
      #expect(host.expansion.isEmpty)
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

    private func appliedSnapshot() throws -> NSDiffableDataSourceSectionSnapshot<String> {
      let dataSource = try #require(
        collectionView.dataSource as? UICollectionViewDiffableDataSource<Int, String>)
      return dataSource.snapshot(for: 0)
    }

    @Test func appliesExpansionChangesWithTheSameIdentifiersAndHierarchy() throws {
      update()
      #expect(try appliedSnapshot().visibleItems == ["a", "b", "c"])
      host.expansion = ["a", "a2"]
      update()
      let expanded = try appliedSnapshot()
      #expect(expanded.isExpanded("a"))
      #expect(expanded.isExpanded("a2"))
      #expect(expanded.visibleItems == ["a", "a1", "a2", "a2x", "b", "c"])
      host.expansion = []
      update()
      #expect(try appliedSnapshot().visibleItems == ["a", "b", "c"])
    }

    @Test func appliesReorderingAndMovesWithTheSameIdentifiers() throws {
      host.expansion = ["a", "a2", "b"]
      update()
      host.roots[0].children!.reverse()
      update()
      #expect(try appliedSnapshot().items == ["a", "a2", "a2x", "a1", "b", "c"])
      let moved = host.roots[0].children!.removeLast()
      host.roots[1].children = [moved]
      update()
      let snapshot = try appliedSnapshot()
      #expect(snapshot.parent(of: "a1") == "b")
      #expect(snapshot.visibleItems == ["a", "a2", "a2x", "b", "a1", "c"])
    }

    @Test func statusOnlyUpdatesPreserveSelectionFocusAndExpansion() throws {
      host.expansion = ["a", "a2"]
      host.single = "a2x"
      host.badge = .text("New")
      update()
      let before = try appliedSnapshot()
      let focused = coordinator.focusedItemID
      host.badge = .progress(0.4, accessibilityLabel: "Uploading")
      update()
      let after = try appliedSnapshot()
      #expect(after.items == before.items)
      #expect(after.visibleItems == before.visibleItems)
      #expect(after.isExpanded("a"))
      #expect(after.isExpanded("a2"))
      #expect(coordinator.selectedItemIDs == ["a2x"])
      #expect(coordinator.focusedItemID == focused)
      #expect(host.expansion == ["a", "a2"])
      #expect(host.single == "a2x")
    }

    @Test func appliesSelectionFromTheBinding() {
      host.single = "c"
      update()
      #expect(coordinator.selectedItemIDs == ["c"])

      host.single = nil
      update()
      #expect(coordinator.selectedItemIDs.isEmpty)
    }

    @Test func physicalModifiedArrowsReorderWithoutChangingSelection() throws {
      host.canReorder = { _ in true }
      host.single = "b"
      host.drop = OutlineDropHandler(
        validate: { _ in .accept(.move) },
        perform: { [host] proposal, _ in
          guard let id = proposal.draggedIDs.first,
            let source = host.roots.firstIndex(where: { $0.id == id }),
            let destination = proposal.insertionIndexAfterRemoval
          else { return false }
          let item = host.roots.remove(at: source)
          host.roots.insert(item, at: destination)
          return true
        })
      update()
      #expect(
        collectionView.handleDirectionalKey(.keyboardDownArrow, modifiers: [.command, .alternate]))
      #expect(host.roots.map(\.id) == ["a", "c", "b"])
      update()
      #expect(coordinator.selectedItemIDs == ["b"])
      #expect(coordinator.focusedItemID == "b")
      #expect(
        collectionView.handleDirectionalKey(.keyboardDownArrow, modifiers: [.command, .alternate]))
      #expect(host.roots.map(\.id) == ["a", "c", "b"])
      #expect(
        collectionView.handleDirectionalKey(.keyboardUpArrow, modifiers: [.command, .alternate]))
      update(layoutDirection: .rightToLeft)
      #expect(try appliedSnapshot().items == ["a", "a1", "a2", "a2x", "b", "c"])
      #expect(host.single == "b")
    }

    @Test func reorderCommandsIgnoreMultipleSelectionIncludingHiddenRows() {
      host.single = "b"
      host.canReorder = { _ in true }
      var performed = false
      host.drop = OutlineDropHandler(
        validate: { _ in .accept(.move) },
        perform: { _, _ in
          performed = true
          return true
        })
      update()
      host.multiple = ["b", "a1"]
      update(multipleSelection: true)
      #expect(!coordinator.canHandleKeyboardAction(.moveUp))
      coordinator.handleKeyboardAction(.moveDown)
      #expect(!performed)
      #expect(host.multiple == ["b", "a1"])
    }

    @Test func registeredReorderCommandsRespectHostValidation() throws {
      host.canReorder = { _ in true }
      host.single = "b"
      var allowed = true
      var performed = false
      host.drop = OutlineDropHandler(
        validate: { _ in allowed ? .accept(.move) : .reject },
        perform: { _, _ in
          performed = true
          return true
        })
      update()
      let command = try #require(
        collectionView.keyCommands?.first {
          $0.input == UIKeyCommand.inputUpArrow && $0.modifierFlags == [.command, .alternate]
        })
      let selector = try #require(command.action)
      #expect(collectionView.canPerformAction(selector, withSender: command))
      allowed = false
      #expect(!collectionView.canPerformAction(selector, withSender: command))
      collectionView.perform(selector, with: command)
      #expect(!performed)
      #expect(
        !collectionView.handleDirectionalKey(
          .keyboardUpArrow, modifiers: [.command, .alternate, .shift]))
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

    @Test func refusesToSelectSectionHeaders() {
      host.sectionTitle = { $0.id == "c" ? "C" : nil }
      update()
      #expect(
        !coordinator.collectionView(
          collectionView, shouldSelectItemAt: IndexPath(item: 2, section: 0)))
    }

    @Test func enablesNativeKeyboardFocusWithoutExpandingOnSelectionQueries() {
      host.isSelectable = { $0.children == nil }
      update()
      let folder = IndexPath(item: 0, section: 0)
      #expect(collectionView.allowsFocus)
      #expect(collectionView.selectionFollowsFocus)
      #expect(coordinator.collectionView(collectionView, canFocusItemAt: folder))
      #expect(!coordinator.collectionView(collectionView, selectionFollowsFocusForItemAt: folder))
      #expect(!coordinator.collectionView(collectionView, shouldSelectItemAt: folder))
      #expect(!coordinator.collectionView(collectionView, shouldSelectItemAt: folder))
      #expect(host.expansion.isEmpty)
      #expect(host.single == nil)
    }

    @Test func horizontalArrowsExpandEnterAndReturnToTheParent() {
      host.single = "a"
      update()
      coordinator.handleKeyboardAction(.expand)
      #expect(host.expansion == ["a"])
      update()
      coordinator.handleKeyboardAction(.expand)
      #expect(host.single == "a1")
      coordinator.handleKeyboardAction(.collapse)
      #expect(host.single == "a")
      coordinator.handleKeyboardAction(.collapse)
      #expect(host.expansion.isEmpty)
    }

    @Test func verticalArrowsMoveFromATouchedRowWithoutActivatingIt() {
      var activated = false
      host.primaryAction = { _ in activated = true }
      host.single = "b"
      update()
      coordinator.handleKeyboardAction(.next)
      #expect(host.single == "c")
      coordinator.handleKeyboardAction(.previous)
      #expect(host.single == "b")
      #expect(!activated)
      #expect(host.expansion.isEmpty)
    }

    @Test func verticalArrowsStartNavigationWithoutAnExistingSelection() {
      update()
      #expect(coordinator.canHandleKeyboardAction(.next))
      coordinator.handleKeyboardAction(.next)
      #expect(host.single == "a")
      #expect(host.expansion.isEmpty)
    }

    @Test func spaceTogglesAContainerAndReturnActivatesWithoutRenaming() {
      var activated: Set<String>?
      host.primaryAction = { activated = $0 }
      host.single = "a"
      update()
      coordinator.handleKeyboardAction(.toggle)
      #expect(host.expansion == ["a"])
      #expect(activated == nil)
      coordinator.handleKeyboardAction(.activate)
      #expect(activated == ["a"])
    }

    @Test func keyboardActivationIgnoresMissingSelections() {
      var activated = false
      host.primaryAction = { _ in activated = true }
      host.single = "missing"
      update()
      #expect(!coordinator.canHandleKeyboardAction(.activate))
      coordinator.handleKeyboardAction(.activate)
      #expect(!activated)
    }

    @Test func keyboardCommandsFollowANewSelectionFromTheHost() {
      var activated: Set<String>?
      host.primaryAction = { activated = $0 }
      host.single = "a"
      update()
      coordinator.handleKeyboardAction(.next)
      #expect(host.single == "b")
      host.single = "c"
      update()
      coordinator.handleKeyboardAction(.activate)
      #expect(activated == ["c"])
    }

    @Test func keyboardFocusCanVisitAHeaderWithoutSelectingOrExpandingIt() {
      host.roots = [.leaf("first"), .group("section", [.leaf("child")])]
      host.sectionTitle = { $0.id == "section" ? "Section" : nil }
      host.single = "first"
      update()
      coordinator.handleKeyboardAction(.next)
      #expect(coordinator.focusedItemID == "section")
      #expect(host.single == "first")
      #expect(host.expansion.isEmpty)
      coordinator.handleKeyboardAction(.activate)
      #expect(host.expansion == ["section"])
      #expect(host.single == "first")
    }

    @Test func arrowsFollowTheActualLayoutDirection() {
      update(layoutDirection: .leftToRight)
      #expect(collectionView.action(for: UIKeyCommand.inputRightArrow) == .expand)
      #expect(collectionView.action(for: UIKeyCommand.inputLeftArrow) == .collapse)
      update(layoutDirection: .rightToLeft)
      #expect(collectionView.action(for: UIKeyCommand.inputLeftArrow) == .expand)
      #expect(collectionView.action(for: UIKeyCommand.inputRightArrow) == .collapse)
    }

    @Test func responderCommandsRouteEachShortcutOnce() throws {
      host.single = "a"
      update()
      let commands = try #require(collectionView.keyCommands)
      let backwards = commands.filter {
        $0.input == UIKeyCommand.inputLeftArrow && $0.modifierFlags.isEmpty
      }
      #expect(backwards.isEmpty)
      let forward = try #require(commands.first { $0.input == UIKeyCommand.inputDownArrow })
      let repeated = try #require(
        collectionView.keyCommands?.first { $0.input == UIKeyCommand.inputDownArrow })
      #expect(repeated === forward)
      #expect(forward.wantsPriorityOverSystemBehavior)
      #expect(!forward.allowsAutomaticMirroring)
      let selector = try #require(forward.action)
      #expect(collectionView.responds(to: selector))
      #expect(collectionView.canPerformAction(selector, withSender: forward))
      // This SwiftPM suite has no running app scene. Check command eligibility and Objective-C
      // dispatch here; the demo UI tests exercise UIKit's real hardware-keyboard routing.
      collectionView.perform(selector, with: forward)
      #expect(host.single == "b")
      #expect(host.expansion.isEmpty)
    }

    @Test func physicalHierarchyArrowsPreserveModifiersAndMapRTL() {
      host.single = "a"
      update()
      #expect(!collectionView.handleDirectionalKey(.keyboardRightArrow, modifiers: .command))
      #expect(host.expansion.isEmpty)
      #expect(collectionView.handleDirectionalKey(.keyboardRightArrow))
      #expect(host.expansion == ["a"])
      update(layoutDirection: .rightToLeft)
      #expect(collectionView.handleDirectionalKey(.keyboardRightArrow))
      #expect(host.expansion.isEmpty)
    }

    @Test func renameFieldsKeepTheirSpacesAndCursorMovement() throws {
      let window = UIWindow(frame: collectionView.frame)
      let controller = UIViewController()
      window.rootViewController = controller
      controller.view.addSubview(collectionView)
      window.makeKeyAndVisible()
      defer { window.isHidden = true }
      let field = UITextField(frame: CGRect(x: 0, y: 0, width: 200, height: 40))
      collectionView.addSubview(field)
      host.single = "a"
      update()
      #expect(collectionView.keyCommands?.contains { $0.input == " " } == true)
      #expect(field.becomeFirstResponder())
      #expect(collectionView.keyCommands?.contains { $0.input == " " } != true)
      #expect(
        collectionView.keyCommands?.contains { $0.input == UIKeyCommand.inputLeftArrow } != true)
    }

    @Test func revealsElementsTheHostSelects() async {
      update()
      host.single = "a2x"
      update()
      for _ in 0..<5 { await Task.yield() }
      #expect(host.expansion == ["a", "a2"])
      update()
      #expect(coordinator.selectedItemIDs == ["a2x"])
    }

    @Test func leavesTheExpansionAloneWhenRevealingIsOff() async {
      host.revealsSelection = false
      update()
      host.single = "a2x"
      update()
      for _ in 0..<5 { await Task.yield() }
      #expect(host.expansion.isEmpty)
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

    @Test func actionsLeaveOutSelectedElementsThatWereRemoved() {
      host.multiple = ["a", "c"]
      update(multipleSelection: true)
      host.roots.removeLast()
      update(multipleSelection: true)
      #expect(host.multiple == ["a", "c"])
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

    @Test func keepsTheSelectionOfRemovedElementsInTheBinding() {
      host.single = "c"
      update()
      host.roots.removeLast()
      update()
      #expect(coordinator.selectedItemIDs.isEmpty)
      #expect(host.single == "c")

      host.roots = sampleRoots
      update()
      #expect(coordinator.selectedItemIDs == ["c"])
    }

    @Test func collapsingKeepsTheSelectionOfHiddenRows() {
      host.expansion = ["a"]
      host.single = "a1"
      update()
      #expect(coordinator.selectedItemIDs == ["a1"])

      host.expansion = []
      update()
      #expect(coordinator.selectedItemIDs.isEmpty)
      #expect(host.single == "a1")

      host.expansion = ["a"]
      update()
      #expect(coordinator.selectedItemIDs == ["a1"])
    }

    @Test func resolvesThePendingDropAgainstDataChangedDuringTheDrag() {
      var validations = 0
      var performed: OutlineDropProposal<String>?
      host.drop = OutlineDropHandler(
        validate: { _ in
          validations += 1
          return .accept(.move)
        },
        perform: { proposal, _ in
          performed = proposal
          return true
        })
      update()
      // Roots a b c: moving c to the end needs no adjustment.
      #expect(
        coordinator.resolveDrop(of: ["c"], at: .insert(into: nil, at: 2))?.proposal
          .insertionIndexAfterRemoval == 2)

      // With a removed, c sits at index 1, before the insertion point.
      host.roots.removeFirst()
      update()
      #expect(coordinator.performDrop(of: ["c"], at: .insert(into: nil, at: 2)))
      #expect(performed?.insertionIndexAfterRemoval == 1)
      #expect(validations == 2)
    }

    @Test func dropsNothingWhenTheDataChangedAwayFromTheDrop() {
      var performed = false
      host.drop = OutlineDropHandler(
        validate: { _ in .accept(.move) },
        perform: { _, _ in
          performed = true
          return true
        })
      update()
      host.roots.removeLast()
      update()
      // c no longer exists, and the root level has no index 3 anymore.
      #expect(!coordinator.performDrop(of: ["c"], at: .onto("a")))
      #expect(!coordinator.performDrop(of: ["b"], at: .insert(into: nil, at: 3)))
      #expect(!performed)
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

    @Test func appendsToTheRootLevelBelowAnExpandedLastFolder() {
      host.roots = [.leaf("a"), .group("z", [.leaf("z1")])]
      host.expansion = ["z"]
      update()
      let rows = OutlineTree(host.roots, children: \.children).visibleRows(expanded: ["z"])
      // Empty space below z1 appends to the root level, not to z.
      #expect(
        coordinator.dropTarget(over: nil, verticalFraction: 0.5, in: rows)
          == .insert(into: nil, at: 2))
      // The lower edge of z1 still inserts after it, inside z.
      #expect(
        coordinator.dropTarget(over: 2, verticalFraction: 0.9, in: rows)
          == .insert(into: "z", at: 1))
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
      await coordinator.springLoadingSettled()
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

    @Test func forgetsSpringLoadedFoldersRemovedDuringTheDrag() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      update()
      await restOn(.onto("a"))
      #expect(coordinator.springLoaded == ["a"])

      host.roots.removeFirst()
      update()
      coordinator.endSpringLoading()
      #expect(coordinator.springLoaded.isEmpty)
      #expect(
        coordinator.sectionSnapshot(expanded: coordinator.displayedExpansion).visibleItems == [
          "b", "c",
        ])
      #expect(host.expansion.isEmpty)
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

    @Test func offersTheHostsSwipeActionsForARow() throws {
      var deleted: String?
      host.trailingSwipeActions = OutlineSwipeActions(
        actions: { id in
          [
            .action("Delete", systemImage: "trash", role: .destructive) { deleted = id },
            .action("Flag", isDisabled: true) {},
            .menu("More", children: []),
            .divider,
            .action("Pin") {},
          ]
        },
        allowsFullSwipe: false)
      update()

      // Row 2 is c.
      let configuration = try #require(
        coordinator.swipeActionsConfiguration(at: IndexPath(item: 2, section: 0), edge: .trailing))
      #expect(configuration.actions.map(\.title) == ["Delete", "Pin"])
      #expect(configuration.actions.first?.style == .destructive)
      #expect(configuration.actions.last?.style == .normal)
      #expect(configuration.actions.first?.image != nil)
      #expect(!configuration.performsFirstActionWithFullSwipe)

      let delete = try #require(configuration.actions.first)
      delete.handler(delete, UIView()) { _ in }
      #expect(deleted == "c")
    }

    @Test func offersNoSwipeWithoutActions() {
      host.trailingSwipeActions = OutlineSwipeActions(actions: { _ in [] }, allowsFullSwipe: true)
      update()
      let row = IndexPath(item: 0, section: 0)
      #expect(coordinator.swipeActionsConfiguration(at: row, edge: .trailing) == nil)
      #expect(coordinator.swipeActionsConfiguration(at: row, edge: .leading) == nil)
    }

    @Test func convertsMenuItemsToUIKitMenus() {
      typealias Coordinator = UIKitOutlineCoordinator<TestItem, Text>
      let elements = Coordinator.menuElements(for: [
        .action("Rename", systemImage: "pencil") {},
        .menu("Move to", children: [.action("Top Level", isDisabled: true) {}]),
        .divider,
        .action("Delete", role: .destructive) {},
      ])
      // A divider splits the items into two inline sections.
      #expect(elements.count == 2)
      let sections = elements.compactMap { $0 as? UIMenu }
      #expect(sections.allSatisfy { $0.options.contains(.displayInline) })

      let first = sections[0].children
      #expect((first[0] as? UIAction)?.title == "Rename")
      let submenu = first[1] as? UIMenu
      #expect(submenu?.title == "Move to")
      #expect((submenu?.children.first as? UIAction)?.attributes.contains(.disabled) == true)
      #expect((sections[1].children.first as? UIAction)?.attributes.contains(.destructive) == true)
    }

    @Test func keepsMenusWithoutDividersFlat() {
      typealias Coordinator = UIKitOutlineCoordinator<TestItem, Text>
      let elements = Coordinator.menuElements(for: [.action("A") {}, .action("B") {}])
      #expect(elements.count == 2)
      #expect(elements.allSatisfy { $0 is UIAction })
    }
  }
#endif
