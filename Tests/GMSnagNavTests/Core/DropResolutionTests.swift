import Testing

@testable import GMSnagNav

@Suite struct DropResolutionTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  private func handler(
    _ validate: @escaping (OutlineDropProposal<String>) -> OutlineDropResult<String>
  ) -> OutlineDropHandler<String> {
    OutlineDropHandler(validate: validate, perform: { _, _ in true })
  }

  @Test func validatesDropTargets() {
    #expect(tree.isValidDropTarget(.root))
    #expect(tree.isValidDropTarget(.onto("a")))
    #expect(tree.isValidDropTarget(.insert(into: "a", at: 2)))
    #expect(!tree.isValidDropTarget(.insert(into: "a", at: 3)))
    #expect(!tree.isValidDropTarget(.onto("missing")))
    #expect(!tree.isValidDropTarget(.insert(into: nil, at: -1)))
  }

  @Test func acceptsWithTheProposedTarget() {
    let result = handler { _ in .accept(.move) }
      .resolve(draggedIDs: ["c"], target: .onto("a"), tree: tree, expanded: [])
    #expect(result?.proposal.target == .onto("a"))
    #expect(result?.operation == .move)
  }

  @Test func rejectsWhenTheHostRejectsOrNothingIsDragged() {
    let accepting = handler { _ in .accept(.move) }
    #expect(accepting.resolve(draggedIDs: [], target: .root, tree: tree, expanded: []) == nil)
    #expect(
      accepting.resolve(draggedIDs: ["missing"], target: .root, tree: tree, expanded: []) == nil)

    let rejecting = handler { _ in .reject }
    #expect(rejecting.resolve(draggedIDs: ["c"], target: .root, tree: tree, expanded: []) == nil)
  }

  @Test func rebuildsTheProposalForRedirects() {
    let result = handler { _ in .redirect(to: .insert(into: nil, at: 3), operation: .copy) }
      .resolve(draggedIDs: ["a"], target: .onto("b"), tree: tree, expanded: [])
    #expect(result?.proposal.target == .insert(into: nil, at: 3))
    #expect(result?.proposal.insertionIndexAfterRemoval == 2)
    #expect(result?.operation == .copy)
  }

  @Test func rejectsRedirectsToInvalidTargets() {
    let result = handler { _ in .redirect(to: .onto("missing"), operation: .move) }
      .resolve(draggedIDs: ["c"], target: .root, tree: tree, expanded: [])
    #expect(result == nil)
  }
}
