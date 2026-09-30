import Testing

@testable import GMSnagNav

@Suite struct OutlineTreeTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  @Test func indexesRootsAndCount() {
    #expect(tree.roots == ["a", "b", "c"])
    #expect(tree.count == 6)
    #expect(tree.duplicateIDs.isEmpty)
  }

  @Test func recordsParentIndexAndDepth() throws {
    let a2x = try #require(tree.node("a2x"))
    #expect(a2x.parent == "a2")
    #expect(a2x.index == 0)
    #expect(a2x.depth == 2)

    let c = try #require(tree.node("c"))
    #expect(c.parent == nil)
    #expect(c.index == 2)
    #expect(c.depth == 0)
  }

  @Test func distinguishesLeavesFromEmptyContainers() {
    #expect(tree.isExpandable("a"))
    #expect(tree.isExpandable("b"))
    #expect(tree.children(of: "b").isEmpty)
    #expect(!tree.isExpandable("c"))
    #expect(!tree.isExpandable("missing"))
  }

  @Test func returnsChildrenForParentsAndRoot() {
    #expect(tree.children(of: nil) == ["a", "b", "c"])
    #expect(tree.children(of: "a") == ["a1", "a2"])
    #expect(tree.children(of: "c").isEmpty)
    #expect(tree.children(of: "missing").isEmpty)
  }

  @Test func looksUpElements() {
    #expect(tree.element("a1") == .leaf("a1"))
    #expect(tree.element("missing") == nil)
    #expect(tree.contains("a2x"))
    #expect(!tree.contains("missing"))
    #expect(tree.parent(of: "a") == nil)
  }

  @Test func listsAncestorsFromParentToRoot() {
    #expect(tree.ancestors(of: "a2x") == ["a2", "a"])
    #expect(tree.ancestors(of: "a").isEmpty)
    #expect(tree.ancestors(of: "missing").isEmpty)
  }

  @Test func detectsDescendants() {
    #expect(tree.isDescendant("a2x", of: "a"))
    #expect(tree.isDescendant("a1", of: "a"))
    #expect(!tree.isDescendant("a", of: "a"))
    #expect(!tree.isDescendant("a", of: "a2x"))
    #expect(!tree.isDescendant("c", of: "a"))
  }

  @Test func supportsChildrenClosure() {
    let tree = OutlineTree(sampleRoots) { item in item.id == "a" ? item.children : nil }
    #expect(tree.children(of: "a") == ["a1", "a2"])
    #expect(!tree.isExpandable("a2"))
    #expect(!tree.contains("a2x"))
  }

  @Test func handlesEmptyInput() {
    let tree = OutlineTree([TestItem](), children: \.children)
    #expect(tree.roots.isEmpty)
    #expect(tree.count == 0)
  }

  @Test func keepsFirstOccurrenceOfDuplicateIDs() throws {
    let roots: [TestItem] = [
      .group("a", [.leaf("x")]),
      .group("b", [.group("x", [.leaf("y")]), .leaf("z")]),
    ]
    let tree = OutlineTree(roots, children: \.children)

    #expect(tree.duplicateIDs == ["x"])
    #expect(tree.parent(of: "x") == "a")
    #expect(tree.children(of: "b") == ["z"])
    #expect(!tree.contains("y"))
    // Siblings after a skipped duplicate get consecutive indices.
    #expect(try #require(tree.node("z")).index == 0)
  }

  @Test func terminatesOnCyclicChildrenProvider() {
    // Every element claims the root as its child, which would recurse forever without the
    // duplicate check.
    let root = TestItem.group("root")
    let tree = OutlineTree([root]) { _ in [root] }
    #expect(tree.count == 1)
    #expect(tree.duplicateIDs == ["root"])
    #expect(tree.children(of: "root").isEmpty)
    #expect(tree.isExpandable("root"))
  }

  @Test func handlesDeepTrees() {
    var item = TestItem.leaf("n500")
    for level in stride(from: 499, through: 0, by: -1) {
      item = .group("n\(level)", [item])
    }
    let tree = OutlineTree([item], children: \.children)
    #expect(tree.count == 501)
    #expect(tree.node("n500")?.depth == 500)
    #expect(tree.ancestors(of: "n500").count == 500)
  }
}
