import Testing

@testable import GMSnagNav

@Suite struct ExpansionChangesTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  @Test func computesIndexPaths() {
    #expect(tree.indexPath(of: "a") == [0])
    #expect(tree.indexPath(of: "a2") == [0, 1])
    #expect(tree.indexPath(of: "a2x") == [0, 1, 0])
    #expect(tree.indexPath(of: "c") == [2])
    #expect(tree.indexPath(of: "missing").isEmpty)
  }

  @Test func reportsNoChangesForEqualStates() {
    let changes = tree.expansionChanges(from: ["a", "a2"], to: ["a2", "a"])
    #expect(changes.isEmpty)
  }

  @Test func expandsTopDownInDisplayOrder() {
    let changes = tree.expansionChanges(from: [], to: ["b", "a2", "a"])
    #expect(changes.expand == ["a", "a2", "b"])
    #expect(changes.collapse.isEmpty)
  }

  @Test func collapsesDeepestFirst() {
    let changes = tree.expansionChanges(from: ["a", "a2", "b"], to: [])
    #expect(changes.collapse == ["a2", "a", "b"])
    #expect(changes.expand.isEmpty)
  }

  @Test func combinesCollapsingAndExpanding() {
    let changes = tree.expansionChanges(from: ["a", "a2"], to: ["a", "b"])
    #expect(changes.collapse == ["a2"])
    #expect(changes.expand == ["b"])
  }

  @Test func keepsExpansionOfChildrenIndependentOfTheirParent() {
    // Collapsing a must not implicitly collapse a2; its state survives for the next expand.
    let changes = tree.expansionChanges(from: ["a", "a2"], to: ["a2"])
    #expect(changes.collapse == ["a"])
    #expect(changes.expand.isEmpty)
  }

  @Test func ignoresLeavesAndUnknownIdentifiers() {
    let changes = tree.expansionChanges(from: ["removed"], to: ["c", "a1", "missing", "a"])
    #expect(changes.expand == ["a"])
    #expect(changes.collapse.isEmpty)
  }

  @Test func findsCollapsedAncestorsToReveal() {
    #expect(tree.ancestorsToReveal("a2x", expanded: []) == ["a", "a2"])
    #expect(tree.ancestorsToReveal("a2x", expanded: ["a"]) == ["a2"])
    #expect(tree.ancestorsToReveal("a2x", expanded: ["a", "a2"]).isEmpty)
    #expect(tree.ancestorsToReveal("c", expanded: []).isEmpty)
    #expect(tree.ancestorsToReveal("missing", expanded: []).isEmpty)
  }
}
