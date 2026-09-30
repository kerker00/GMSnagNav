import Testing

@testable import GMSnagNav

@Suite struct OutlineDropTargetTests {
  @Test func buildsTargetsWithConvenienceConstructors() {
    #expect(OutlineDropTarget.onto("a") == OutlineDropTarget(parent: "a", placement: .onto))
    #expect(OutlineDropTarget<String>.root == OutlineDropTarget(parent: nil, placement: .onto))
    #expect(
      OutlineDropTarget.insert(into: "a", at: 1)
        == OutlineDropTarget(parent: "a", placement: .insert(childIndex: 1)))
  }

  @Test func exposesChildIndexOnlyForInsertions() {
    #expect(OutlineDropTarget<String>.insert(into: nil, at: 3).childIndex == 3)
    #expect(OutlineDropTarget.onto("a").childIndex == nil)
  }

  @Test func publicInitDefaultsToUnadjustedIndex() {
    let proposal = OutlineDropProposal(draggedIDs: ["x"], target: .insert(into: "a", at: 2))
    #expect(proposal.insertionIndexAfterRemoval == 2)
    #expect(!proposal.isDroppingIntoOwnSubtree)
    #expect(!proposal.isTargetExpanded)
  }
}

@Suite struct OutlineDropProposalTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  private func proposal(
    _ dragged: [String], _ target: OutlineDropTarget<String>, expanded: Set<String> = []
  ) -> OutlineDropProposal<String> {
    OutlineDropProposal(draggedIDs: dragged, target: target, tree: tree, expanded: expanded)
  }

  @Test func ordersDraggedIDsInDisplayOrderWithoutDuplicatesOrUnknownIDs() {
    let result = proposal(["c", "a2x", "missing", "a1", "c"], .root)
    #expect(result.draggedIDs == ["a1", "a2x", "c"])
  }

  @Test func detectsDropsIntoOwnSubtree() {
    #expect(proposal(["a"], .onto("a")).isDroppingIntoOwnSubtree)
    #expect(proposal(["a"], .onto("a2")).isDroppingIntoOwnSubtree)
    #expect(proposal(["a"], .insert(into: "a2", at: 0)).isDroppingIntoOwnSubtree)
    #expect(proposal(["c", "a"], .onto("a2x")).isDroppingIntoOwnSubtree)
  }

  @Test func allowsDropsOutsideOwnSubtree() {
    #expect(!proposal(["a2"], .onto("b")).isDroppingIntoOwnSubtree)
    #expect(!proposal(["a2"], .onto("a")).isDroppingIntoOwnSubtree)
    #expect(!proposal(["a"], .root).isDroppingIntoOwnSubtree)
    #expect(!proposal(["a"], .insert(into: nil, at: 3)).isDroppingIntoOwnSubtree)
  }

  @Test func reportsTargetExpansion() {
    #expect(proposal(["c"], .onto("a"), expanded: ["a"]).isTargetExpanded)
    #expect(!proposal(["c"], .onto("a")).isTargetExpanded)
    #expect(!proposal(["c"], .root, expanded: ["a"]).isTargetExpanded)
  }

  @Test func adjustsInsertionIndexForDraggedSiblingsBeforeIt() {
    // Roots: a(0) b(1) c(2). Moving a to the end (index 3) lands at index 2 after removal.
    #expect(proposal(["a"], .insert(into: nil, at: 3)).insertionIndexAfterRemoval == 2)
    // Moving a and b before c (index 2) lands at index 0 after removal.
    #expect(proposal(["a", "b"], .insert(into: nil, at: 2)).insertionIndexAfterRemoval == 0)
    // Moving c up to the front needs no adjustment.
    #expect(proposal(["c"], .insert(into: nil, at: 0)).insertionIndexAfterRemoval == 0)
  }

  @Test func doesNotAdjustForDraggedItemsFromOtherParents() {
    // a1 lives in a, not in the root level, so it does not shift root indices.
    #expect(proposal(["a1"], .insert(into: nil, at: 2)).insertionIndexAfterRemoval == 2)
  }

  @Test func leavesOntoDropsWithoutIndex() {
    #expect(proposal(["c"], .onto("a")).insertionIndexAfterRemoval == nil)
  }
}
