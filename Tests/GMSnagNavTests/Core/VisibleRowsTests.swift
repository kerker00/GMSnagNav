import Testing

@testable import GMSnagNav

@Suite struct VisibleRowsTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  @Test func showsOnlyRootsWhenNothingIsExpanded() {
    let rows = tree.visibleRows(expanded: [])
    #expect(rows.map(\.id) == ["a", "b", "c"])
    #expect(rows.allSatisfy { $0.depth == 0 && $0.parent == nil && !$0.isExpanded })
  }

  @Test func showsChildrenOfExpandedElementsInDisplayOrder() {
    let rows = tree.visibleRows(expanded: ["a"])
    #expect(rows.map(\.id) == ["a", "a1", "a2", "b", "c"])
    #expect(rows.map(\.depth) == [0, 1, 1, 0, 0])
  }

  @Test func showsDeeperLevelsOnlyWhenAllAncestorsAreExpanded() {
    // a2 is expanded, but its parent a is collapsed, so a2x stays hidden.
    #expect(tree.visibleRows(expanded: ["a2"]).map(\.id) == ["a", "b", "c"])

    let rows = tree.visibleRows(expanded: ["a", "a2"])
    #expect(rows.map(\.id) == ["a", "a1", "a2", "a2x", "b", "c"])
    #expect(rows.first { $0.id == "a2x" }?.depth == 2)
  }

  @Test func describesEachRow() throws {
    let rows = tree.visibleRows(expanded: ["a", "b"])

    let a = try #require(rows.first { $0.id == "a" })
    #expect(a.isExpandable && a.isExpanded)
    #expect(a.childCount == 2)

    let a2 = try #require(rows.first { $0.id == "a2" })
    #expect(a2.parent == "a")
    #expect(a2.index == 1)
    #expect(a2.isExpandable && !a2.isExpanded)
    #expect(a2.childCount == 1)

    // An expanded empty container is expanded but shows no children.
    let b = try #require(rows.first { $0.id == "b" })
    #expect(b.isExpandable && b.isExpanded)
    #expect(b.childCount == 0)

    let c = try #require(rows.first { $0.id == "c" })
    #expect(!c.isExpandable && !c.isExpanded)
  }

  @Test func ignoresLeavesAndUnknownIdentifiersInExpansion() {
    let rows = tree.visibleRows(expanded: ["c", "a1", "removed"])
    #expect(rows.map(\.id) == ["a", "b", "c"])
    #expect(rows.first { $0.id == "c" }?.isExpanded == false)
  }

  @Test func returnsNoRowsForAnEmptyTree() {
    let tree = OutlineTree([TestItem](), children: \.children)
    #expect(tree.visibleRows(expanded: ["a"]).isEmpty)
  }

  @Test func handlesDeepFullyExpandedTrees() {
    var item = TestItem.leaf("n500")
    for level in stride(from: 499, through: 0, by: -1) {
      item = .group("n\(level)", [item])
    }
    let tree = OutlineTree([item], children: \.children)
    let expanded = Set((0..<500).map { "n\($0)" })
    let rows = tree.visibleRows(expanded: expanded)
    #expect(rows.count == 501)
    #expect(rows.last?.depth == 500)
  }
}
