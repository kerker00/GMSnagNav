import Testing

@testable import GMSnagNav

@Suite struct SpringLoadingTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  @Test func keepsElementsThatContainTheTarget() {
    #expect(tree.springLoadedToClose(["a", "a2"], targetParent: "a2x").isEmpty)
    #expect(tree.springLoadedToClose(["a", "a2"], targetParent: "a2").isEmpty)
  }

  @Test func closesElementsTheTargetLeft() {
    // Moving from inside a2 to a's other child a1 closes a2 but keeps a.
    #expect(tree.springLoadedToClose(["a", "a2"], targetParent: "a1") == ["a2"])
    // Moving to the root level closes both, deepest first.
    #expect(tree.springLoadedToClose(["a", "a2"], targetParent: nil) == ["a2", "a"])
  }

  @Test func closesUnrelatedElements() {
    #expect(tree.springLoadedToClose(["a"], targetParent: "b") == ["a"])
  }
}
