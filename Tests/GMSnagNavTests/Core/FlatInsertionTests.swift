import Testing

@testable import GMSnagNav

@Suite struct FlatInsertionTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  /// Visible rows with `a` and `a2` expanded:
  ///
  /// ```text
  /// 0 a
  /// 1   a1
  /// 2   a2
  /// 3     a2x
  /// 4 b
  /// 5 c
  /// ```
  var rows: [VisibleRow<String>] { tree.visibleRows(expanded: ["a", "a2"]) }

  @Test func insertsAtTheTopOfTheRootLevel() {
    #expect(tree.dropTarget(forGap: 0, in: rows) == .insert(into: nil, at: 0))
  }

  @Test func insertsAsFirstChildBelowAnExpandedElement() {
    #expect(tree.dropTarget(forGap: 1, in: rows) == .insert(into: "a", at: 0))
    #expect(tree.dropTarget(forGap: 3, in: rows) == .insert(into: "a2", at: 0))
  }

  @Test func insertsBetweenSiblings() {
    #expect(tree.dropTarget(forGap: 2, in: rows) == .insert(into: "a", at: 1))
    #expect(tree.dropTarget(forGap: 5, in: rows) == .insert(into: nil, at: 2))
  }

  @Test func resolvesLevelChangesToTheRowAbove() {
    // Between a2x (depth 2) and b (depth 0), the items go to the end of a2, after a2x.
    #expect(tree.dropTarget(forGap: 4, in: rows) == .insert(into: "a2", at: 1))
  }

  @Test func keepsItemsInTheirFolderWhenMovedToItsBottom() {
    // Rows with only a expanded: a, a1, a2, b, c. a1 moved below a2 stays in a, at its end.
    let rows = tree.visibleRows(expanded: ["a"])
    let target = tree.dropTarget(forGap: 3, in: rows)
    #expect(target == .insert(into: "a", at: 2))
    let proposal = OutlineDropProposal(
      draggedIDs: ["a1"], target: target, tree: tree, expanded: ["a"])
    #expect(proposal.insertionIndexAfterRemoval == 1)
  }

  @Test func appendsItemsFromOutsideToTheEndOfAnExpandedFolder() {
    // c, coming from the root level, lands at the end of a when dropped below a's last child.
    let rows = tree.visibleRows(expanded: ["a"])
    let proposal = OutlineDropProposal(
      draggedIDs: ["c"], target: tree.dropTarget(forGap: 3, in: rows), tree: tree,
      expanded: ["a"])
    #expect(proposal.target == .insert(into: "a", at: 2))
    #expect(proposal.insertionIndexAfterRemoval == 2)
  }

  @Test func appendsToTheLastRowsLevelBelowTheLastRow() {
    #expect(tree.dropTarget(forGap: 6, in: rows) == .insert(into: nil, at: 3))
    // When the last visible row is nested, the gap below it appends to its folder.
    let nested = OutlineTree([TestItem.group("f", [.leaf("x")])], children: \.children)
    let nestedRows = nested.visibleRows(expanded: ["f"])
    #expect(nested.dropTarget(forGap: 2, in: nestedRows) == .insert(into: "f", at: 1))
  }

  @Test func clampsOutOfRangeGaps() {
    #expect(tree.dropTarget(forGap: -1, in: rows) == .insert(into: nil, at: 0))
    #expect(tree.dropTarget(forGap: 99, in: rows) == .insert(into: nil, at: 3))
  }

  @Test func handlesAnEmptyOutline() {
    let tree = OutlineTree([TestItem](), children: \.children)
    #expect(tree.dropTarget(forGap: 0, in: []) == .insert(into: nil, at: 0))
  }

  @Test func combinesWithProposalsToDetectMovesIntoOwnSubtree() {
    // Dragging a into the gap below a2 would place it inside itself.
    let target = tree.dropTarget(forGap: 3, in: rows)
    let proposal = OutlineDropProposal(
      draggedIDs: ["a"], target: target, tree: tree, expanded: ["a", "a2"])
    #expect(proposal.isDroppingIntoOwnSubtree)
  }

  @Test func combinesWithProposalsToAdjustMovesWithinTheSameLevel() {
    // Dragging a (root index 0) into the gap above c (root index 2) lands at index 1.
    let target = tree.dropTarget(forGap: 5, in: rows)
    let proposal = OutlineDropProposal(
      draggedIDs: ["a"], target: target, tree: tree, expanded: ["a", "a2"])
    #expect(proposal.insertionIndexAfterRemoval == 1)
  }
}
