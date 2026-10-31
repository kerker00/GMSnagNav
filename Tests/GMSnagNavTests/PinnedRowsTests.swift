import SwiftUI
import Testing

@testable import GMSnagNav

@MainActor
@Suite struct PinnedRowsTests {
  let tree = OutlineTree(sampleRoots, children: \.children)
  let pins: (TestItem) -> Bool = { ["a", "a1"].contains($0.id) }

  private func handler(
    _ validate: @escaping (OutlineDropProposal<String>) -> OutlineDropResult<String> = { _ in
      .accept(.move)
    }
  ) -> OutlineDropHandler<String> {
    OutlineDropHandler(validate: validate, perform: { _, _ in true })
  }

  @Test func modifierOrderCannotEnableDraggingOrReorderingOfPinnedRows() {
    let first = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlinePinned(pins).outlineDraggable().outlineReorderable()
      .onOutlineDrop(perform: { _, _ in true }).behavior
    let last = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineDraggable().outlineReorderable().onOutlineDrop(perform: { _, _ in true })
      .outlinePinned(pins).behavior
    for behavior in [first, last] {
      #expect(!behavior.isDraggable(sampleRoots[0]))
      #expect(behavior.isDraggable(sampleRoots[1]))
      #expect(behavior.canSelect(sampleRoots[0]))
      #expect(!behavior.reorder("a", direction: .down, tree: tree, expanded: []))
      #expect(!behavior.reorder("b", direction: .up, tree: tree, expanded: []))
      #expect(behavior.reorder("b", direction: .down, tree: tree, expanded: []))
      #expect(!behavior.reorder("a2", direction: .up, tree: tree, expanded: ["a"]))
    }
  }

  @Test func validatesTheAdjustedTargetAtRootAndNestedLevels() {
    var received: [OutlineDropTarget<String>] = []
    let drop = handler {
      received.append($0.target)
      return .accept(.move)
    }
    let root = drop.resolve(
      draggedIDs: ["c"], target: .insert(into: nil, at: 0), tree: tree, expanded: [],
      isPinned: pins)
    #expect(root?.proposal.target == .insert(into: nil, at: 1))
    let nested = drop.resolve(
      draggedIDs: ["c"], target: .insert(into: "a", at: 0), tree: tree, expanded: ["a"],
      isPinned: pins)
    #expect(nested?.proposal.target == .insert(into: "a", at: 1))
    #expect(nested?.proposal.isTargetExpanded == true)
    #expect(received == [.insert(into: nil, at: 1), .insert(into: "a", at: 1)])
  }

  @Test func protectsTheWholePinnedSpanIncludingInterleavedHostData() {
    let tree = OutlineTree<TestItem>(
      [.leaf("p1"), .leaf("normal"), .leaf("p2"), .leaf("moving")], children: \.children)
    for index in 0...3 {
      let result = handler().resolve(
        draggedIDs: ["moving"], target: .insert(into: nil, at: index), tree: tree,
        expanded: [], isPinned: { $0.id.hasPrefix("p") })
      #expect(result?.proposal.target == .insert(into: nil, at: 3))
    }
    #expect(tree.roots == ["p1", "normal", "p2", "moving"])
  }

  @Test func leavesUnprotectedPositionsAndContainerDropsToTheHost() {
    let drop = handler()
    for target: OutlineDropTarget<String> in [
      .root, .onto("a"), .onto("a1"), .insert(into: nil, at: 2),
      .insert(into: "a", at: 1), .insert(into: "b", at: 0),
    ] {
      let result = drop.resolve(
        draggedIDs: ["c"], target: target, tree: tree, expanded: [], isPinned: pins)
      #expect(result?.proposal.target == target)
    }
  }

  @Test func skipsPinnedSourcesBeforeNormalizingASelection() {
    let result = handler().resolve(
      draggedIDs: ["c", "a", "a1", "a2", "a2x", "missing"], target: .root,
      tree: tree, expanded: [], isPinned: pins)
    #expect(result?.proposal.draggedIDs == ["a2", "c"])
    #expect(
      handler().resolve(
        draggedIDs: ["a", "a1"], target: .root, tree: tree, expanded: [], isPinned: pins) == nil)
  }

  @Test func movingAnAncestorStillCarriesPinnedDescendants() {
    let result = handler().resolve(
      draggedIDs: ["a"], target: .root, tree: tree, expanded: [],
      isPinned: { $0.id == "a1" })
    #expect(result?.proposal.draggedIDs == ["a"])
  }

  @Test func keepsMoveAndCopyIndicesCorrect() {
    let result = handler { .accept($0.isCopyRequested ? .copy : .move) }
      .resolve(
        draggedIDs: ["b"], target: .insert(into: nil, at: 3), tree: tree, expanded: [],
        isPinned: pins)
    #expect(result?.proposal.target.childIndex == 3)
    #expect(result?.proposal.insertionIndexAfterRemoval == 2)
    let copy = handler { .accept($0.isCopyRequested ? .copy : .move) }
      .resolve(
        draggedIDs: ["c"], target: .insert(into: nil, at: 0), tree: tree, expanded: [],
        isCopyRequested: true, isPinned: pins)
    #expect(copy?.operation == .copy)
    #expect(copy?.proposal.isCopyRequested == true)
    #expect(copy?.proposal.target.childIndex == 1)
  }

  @Test func revalidatesHostRedirectsThatEnterThePinnedSpan() {
    var targets: [OutlineDropTarget<String>] = []
    let drop = handler { proposal in
      targets.append(proposal.target)
      if proposal.target == .onto("a1") {
        return .redirect(to: .insert(into: nil, at: 0), operation: .move)
      }
      return .accept(.copy)
    }
    let result = drop.resolve(
      draggedIDs: ["c"], target: .onto("a1"), tree: tree, expanded: [], isPinned: pins)
    #expect(targets == [.onto("a1"), .insert(into: nil, at: 1)])
    #expect(result?.proposal.target == .insert(into: nil, at: 1))
    #expect(result?.operation == .copy)
  }

  @Test func rejectsAdjustedRedirectsTheHostDoesNotAccept() {
    for secondResult: OutlineDropResult<String> in [
      .reject, .redirect(to: .insert(into: nil, at: 0), operation: .move),
      .redirect(to: .onto("missing"), operation: .move),
    ] {
      let drop = handler { proposal in
        proposal.target == .onto("a1")
          ? .redirect(to: .insert(into: nil, at: 0), operation: .move) : secondResult
      }
      #expect(
        drop.resolve(
          draggedIDs: ["c"], target: .onto("a1"), tree: tree, expanded: [], isPinned: pins) == nil)
    }
    #expect(
      handler { _ in .reject }.resolve(
        draggedIDs: ["c"], target: .insert(into: nil, at: 0), tree: tree, expanded: [],
        isPinned: pins) == nil)
  }

  @Test func acceptsAnEquivalentRedirectOnRevalidation() {
    let result = handler { _ in .redirect(to: .insert(into: nil, at: 1), operation: .copy) }
      .resolve(
        draggedIDs: ["c"], target: .onto("a1"), tree: tree, expanded: [],
        isPinned: { ["a", "b"].contains($0.id) })
    // A host insisting on index 1 conflicts with the adjusted index 2.
    #expect(result == nil)
    let accepted = handler { proposal in
      .redirect(
        to: .insert(into: nil, at: proposal.target.childIndex == nil ? 0 : 1), operation: .copy)
    }.resolve(draggedIDs: ["c"], target: .onto("a1"), tree: tree, expanded: [], isPinned: pins)
    #expect(accepted?.proposal.target == .insert(into: nil, at: 1))
    #expect(accepted?.operation == .copy)
  }

  @Test func invalidTargetsAreRejectedBeforePinningCanClampThem() {
    for target: OutlineDropTarget<String> in [
      .insert(into: nil, at: -1), .insert(into: nil, at: 4), .onto("missing"),
    ] {
      #expect(
        handler().resolve(
          draggedIDs: ["c"], target: target, tree: tree, expanded: [], isPinned: pins) == nil)
    }
  }
}
