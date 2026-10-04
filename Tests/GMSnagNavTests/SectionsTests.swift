import Testing

@testable import GMSnagNav

@Suite struct SectionsTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  /// Treats `a` and the nested `a2` as sections; only the root element may become one.
  private var behavior: OutlineBehavior<TestItem> {
    var behavior = OutlineBehavior<TestItem>()
    behavior.sectionTitle = { ["a", "a2"].contains($0.id) ? $0.id.uppercased() : nil }
    return behavior
  }

  @Test func onlyRootElementsHeadSections() {
    #expect(behavior.sectionTitle(of: "a", in: tree) == "A")
    #expect(behavior.sectionTitle(of: "a2", in: tree) == nil)
    #expect(behavior.sectionTitle(of: "c", in: tree) == nil)
    #expect(behavior.sectionTitle(of: "missing", in: tree) == nil)
    #expect(OutlineBehavior<TestItem>().sectionTitle(of: "a", in: tree) == nil)
  }

  @Test func sectionHeadersAreNeverSelectable() {
    #expect(!behavior.canSelect("a", in: tree))
    #expect(behavior.canSelect("a1", in: tree))
    #expect(behavior.canSelect("c", in: tree))
    #expect(!behavior.canSelect("missing", in: tree))
  }

  @Test func entriesOfSectionsAreNotIndented() {
    #expect(behavior.indentationDepth(of: "a", in: tree) == 0)
    #expect(behavior.indentationDepth(of: "a1", in: tree) == 0)
    #expect(behavior.indentationDepth(of: "a2x", in: tree) == 1)
    #expect(behavior.indentationDepth(of: "c", in: tree) == 0)
    #expect(OutlineBehavior<TestItem>().indentationDepth(of: "a2x", in: tree) == 2)
  }
}
