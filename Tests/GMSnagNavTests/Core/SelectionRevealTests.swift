import Testing

@testable import GMSnagNav

@Suite struct SelectionRevealTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  @Test func revealsTheHostsSelectionInsideCollapsedContainers() {
    var reveal = SelectionReveal<String>()
    #expect(reveal.hostSelected(["a2x"], in: tree, expanded: []) == ["a", "a2"])
    #expect(reveal.pending == "a2x")
    reveal.didReveal()
    #expect(reveal.pending == nil)
  }

  @Test func revealsTheRestoredSelectionOnTheFirstUpdate() {
    var reveal = SelectionReveal<String>()
    #expect(reveal.hostSelected(["c"], in: tree, expanded: []).isEmpty)
    #expect(reveal.pending == "c")
  }

  @Test func ignoresUnchangedSelections() {
    var reveal = SelectionReveal<String>()
    _ = reveal.hostSelected(["a2x"], in: tree, expanded: [])
    reveal.didReveal()
    #expect(reveal.hostSelected(["a2x"], in: tree, expanded: []).isEmpty)
    #expect(reveal.pending == nil)
  }

  @Test func neverRevealsWhatTheUserSelected() {
    var reveal = SelectionReveal<String>()
    reveal.userSelected(["a2x"])
    #expect(reveal.hostSelected(["a2x"], in: tree, expanded: []).isEmpty)
    #expect(reveal.pending == nil)
  }

  @Test func revealsTheFirstNewlySelectedElementInDisplayOrder() {
    var reveal = SelectionReveal<String>()
    reveal.userSelected(["c"])
    #expect(reveal.hostSelected(["c", "a2x", "a1"], in: tree, expanded: ["a"]).isEmpty)
    #expect(reveal.pending == "a1")
  }

  @Test func ignoresElementsMissingFromTheTree() {
    var reveal = SelectionReveal<String>()
    #expect(reveal.hostSelected(["missing"], in: tree, expanded: []).isEmpty)
    #expect(reveal.pending == nil)
  }
}
