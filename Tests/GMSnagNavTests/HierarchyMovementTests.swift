import SwiftUI
import Testing

@testable import GMSnagNav

@MainActor
@Suite struct HierarchyMovementTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  private func behavior(
    validate: @escaping (OutlineDropProposal<String>) -> OutlineDropResult<String> = { _ in
      .accept(.move)
    }
  ) -> OutlineBehavior<TestItem> {
    SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineHierarchyMovable()
      .onOutlineDrop(validate: validate, perform: { _, _ in true }).behavior
  }

  @Test func indentsIntoTheImmediateContainerIncludingAnEmptyOne() {
    let proposal = behavior().hierarchyProposal(
      for: "c", direction: .indent, tree: tree, expanded: [])
    #expect(proposal?.target == .insert(into: "b", at: 0))
    #expect(proposal?.draggedIDs == ["c"])
    #expect(proposal?.insertionIndexAfterRemoval == 0)
    let intoNonempty = behavior().hierarchyProposal(
      for: "b", direction: .indent, tree: tree, expanded: ["a", "a2"])
    #expect(intoNonempty?.target == .insert(into: "a", at: 2))
    #expect(intoNonempty?.isTargetExpanded == true)
  }

  @Test func outdentsAfterTheParentWithoutMovingItsOtherChildren() {
    let proposal = behavior().hierarchyProposal(
      for: "a2x", direction: .outdent, tree: tree, expanded: [])
    #expect(proposal?.target == .insert(into: "a", at: 2))
    #expect(proposal?.draggedIDs == ["a2x"])
    let root = behavior().hierarchyProposal(
      for: "a1", direction: .outdent, tree: tree, expanded: [])
    #expect(root?.target == .insert(into: nil, at: 1))
    #expect(root?.insertionIndexAfterRemoval == 1)
  }

  @Test func boundariesLeavesAndMissingRowsHaveNoAlternativeDestination() {
    let behavior = behavior()
    for (id, direction): (String, OutlineHierarchyDirection) in [
      ("a", .indent), ("c", .outdent), ("a2", .indent), ("missing", .indent),
    ] {
      #expect(
        behavior.hierarchyProposal(for: id, direction: direction, tree: tree, expanded: []) == nil)
    }
  }

  @Test func sectionHeadersAndTheirRootBoundaryAreNotCrossed() {
    var behavior = behavior()
    behavior.sectionTitle = { $0.id == "a" ? "Section" : nil }
    #expect(
      behavior.hierarchyProposal(for: "b", direction: .indent, tree: tree, expanded: []) == nil)
    #expect(
      behavior.hierarchyProposal(for: "a1", direction: .outdent, tree: tree, expanded: []) == nil)
    #expect(
      behavior.hierarchyProposal(for: "a2x", direction: .outdent, tree: tree, expanded: []) != nil)
    behavior.sectionTitle = { $0.id == "b" ? "Section" : nil }
    #expect(
      behavior.hierarchyProposal(for: "b", direction: .indent, tree: tree, expanded: []) == nil)
  }

  @Test func protectsPinsWithoutDisablingPinnedContainerDestinations() {
    var behavior = behavior()
    behavior.isPinned = { $0.id == "c" }
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) == nil)
    behavior.isPinned = { $0.id == "b" }
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) != nil)
    behavior.isPinned = { ["a", "b"].contains($0.id) }
    #expect(
      behavior.hierarchyProposal(for: "a1", direction: .outdent, tree: tree, expanded: []) == nil)
    behavior.isPinned = { $0.id == "a" }
    #expect(
      behavior.hierarchyProposal(for: "a1", direction: .outdent, tree: tree, expanded: []) != nil)
  }

  @Test func onlyExactMoveAnswersCanExecuteTheNamedStep() {
    for result: OutlineDropResult<String> in [
      .reject, .accept(.copy), .redirect(to: .onto("b"), operation: .move),
      .redirect(to: .insert(into: nil, at: 0), operation: .move),
      .redirect(to: .insert(into: "a", at: 0), operation: .move),
    ] {
      #expect(
        behavior(validate: { _ in result }).hierarchyProposal(
          for: "c", direction: .indent, tree: tree, expanded: []) == nil)
    }
    #expect(
      behavior(validate: { _ in
        .redirect(to: .insert(into: "b", at: 0), operation: .move)
      }).hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) != nil)
  }

  @Test func disabledHierarchyDoesNotReadTheLiveModel() {
    var reads = 0
    let actions = OutlineActions(
      data: {
        reads += 1
        return sampleRoots
      }, children: \.children, perform: { _, _ in true })
    let behavior = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .onOutlineDrop(actions).behavior
    let tree = OutlineTree(sampleRoots, children: \.children)
    for direction in OutlineHierarchyDirection.allCases {
      #expect(
        behavior.hierarchyProposal(for: "c", direction: direction, tree: tree, expanded: []) == nil)
    }
    #expect(reads == 0)
  }

  @Test(arguments: [false, true])
  func subsequentUpdatesCancelScheduledRevealOnlyWhenStructureChanges(structuralChange: Bool) async
  {
    let driver = OutlineHierarchyReveal<String>()
    let before = OutlineTree<TestItem>(
      [.group("a", [.leaf("x")]), .group("b"), .leaf("c")], children: \.children)
    let moved = OutlineTree<TestItem>(
      [.group("a", [.leaf("x")]), .group("b", [.leaf("c")])], children: \.children)
    let anotherMove = OutlineTree<TestItem>(
      [.group("a"), .group("b", [.leaf("c"), .leaf("x")])], children: \.children)
    driver.record(
      OutlineDropProposal(draggedIDs: ["c"], target: .insert(into: "b", at: 0)),
      selection: ["c"], focused: true)
    var reveals = 0
    driver.update(tree: moved, previous: before, selection: ["c"], navigationPending: false) { _ in
      reveals += 1
    }
    driver.update(
      tree: structuralChange ? anotherMove : moved, previous: moved, selection: ["c"],
      navigationPending: false
    ) {
      _ in reveals += 1
    }
    await driver.settled()
    #expect(reveals == (structuralChange ? 0 : 1))
  }

  @Test func requiresItsOwnOptInButNotDraggingReorderingOrSelectionEligibility() {
    var behavior = behavior()
    #expect(behavior.canDrag == nil)
    #expect(behavior.canReorder == nil)
    behavior.isSelectable = { _ in false }
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) != nil)
    behavior.canMoveHierarchy = nil
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) == nil)
    behavior.canMoveHierarchy = { _ in true }
    behavior.drop = nil
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) == nil)
  }

  @Test func liveEligibilityAndPinsAreNotFrozenByBodyObservation() {
    var allowed = true
    var pinned = false
    var behavior = behavior()
    behavior.canMoveHierarchy = { _ in allowed }
    behavior.isPinned = { _ in pinned }
    behavior = behavior.resolvingPinnedRows(in: tree).observingHierarchy(in: tree)
    allowed = false
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) == nil)
    allowed = true
    pinned = true
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) == nil)
  }

  @Test func theFacadeReadsHostChangesBeforeTheNextRendererUpdate() {
    var roots = sampleRoots
    let actions = OutlineActions(data: { roots }, children: \.children, perform: { _, _ in true })
    let behavior = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineHierarchyMovable().onOutlineDrop(actions).behavior
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) != nil)
    roots[1] = .leaf("b")
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) == nil)
  }

  @Test func renamingBlocksMovementAndShortcutOptOutDoesNotRemoveAXEligibility() {
    let optedOut = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineHierarchyMovable(keyboardShortcuts: false)
      .onOutlineDrop { _, _ in true }.behavior
    #expect(!optedOut.hierarchyKeyboardShortcuts)
    #expect(
      optedOut.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) != nil)
    var behavior = behavior()
    behavior.renaming = OutlineRenameHandler(
      renaming: .constant("a1"), canRename: { _ in true }, onRename: { _, _ in })
    #expect(
      behavior.hierarchyProposal(for: "c", direction: .indent, tree: tree, expanded: []) == nil)
  }

  @Test func revealWaitsForTheModelAndRunsOnceWithoutChangingSelection() async {
    let driver = OutlineHierarchyReveal<String>()
    let proposal = OutlineDropProposal(draggedIDs: ["c"], target: .insert(into: "b", at: 0))
    driver.record(proposal, selection: ["c"], focused: true)
    var requests: [OutlineHierarchyReveal<String>.Request] = []
    driver.update(tree: tree, previous: tree, selection: ["c"], navigationPending: false) {
      requests.append($0)
    }
    await driver.settled()
    #expect(requests.isEmpty)
    let changed = OutlineTree<TestItem>([.group("b", [.leaf("c")])], children: \.children)
    driver.update(tree: changed, previous: tree, selection: ["c"], navigationPending: false) {
      requests.append($0)
    }
    await driver.settled()
    #expect(requests.count == 1)
    #expect(requests[0].source == "c")
    #expect(requests[0].preservesKeyboardFocus)
    driver.update(tree: changed, previous: changed, selection: ["c"], navigationPending: false) {
      requests.append($0)
    }
    await driver.settled()
    #expect(requests.count == 1)
  }

  @Test(arguments: [false, true])
  func newSelectionOrExplicitNavigationCancelsThePendingReveal(navigation: Bool) async {
    let driver = OutlineHierarchyReveal<String>()
    driver.record(
      OutlineDropProposal(draggedIDs: ["c"], target: .insert(into: "b", at: 0)),
      selection: ["c"], focused: false)
    let changed = OutlineTree<TestItem>([.group("b", [.leaf("c")])], children: \.children)
    var called = false
    driver.update(
      tree: changed, previous: tree, selection: navigation ? ["c"] : ["b"],
      navigationPending: navigation
    ) { _ in called = true }
    await driver.settled()
    #expect(!called)
  }

  @Test func aDifferentStructuralChangeAndDetachCancelThePendingReveal() async {
    let driver = OutlineHierarchyReveal<String>()
    let proposal = OutlineDropProposal(draggedIDs: ["c"], target: .insert(into: "b", at: 0))
    driver.record(proposal, selection: ["c"], focused: false)
    let foreign = OutlineTree<TestItem>([.group("a", [.leaf("c")])], children: \.children)
    let correct = OutlineTree<TestItem>([.group("b", [.leaf("c")])], children: \.children)
    var called = false
    driver.update(tree: foreign, previous: tree, selection: ["c"], navigationPending: false) { _ in
      called = true
    }
    driver.update(tree: correct, previous: foreign, selection: ["c"], navigationPending: false) {
      _ in called = true
    }
    await driver.settled()
    #expect(!called)
    driver.record(proposal, selection: ["c"], focused: false)
    driver.update(tree: correct, previous: tree, selection: ["c"], navigationPending: false) { _ in
      called = true
    }
    driver.cancel()
    await Task.yield()
    #expect(!called)
  }
}
