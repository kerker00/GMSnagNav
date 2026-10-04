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

  @Test func passesTheCopyRequestToTheHost() {
    let copying = handler { proposal in
      proposal.isCopyRequested ? .redirect(to: .onto("b"), operation: .copy) : .accept(.move)
    }
    let copied = copying.resolve(
      draggedIDs: ["c"], target: .root, tree: tree, expanded: [], isCopyRequested: true)
    #expect(copied?.proposal.isCopyRequested == true)
    #expect(copied?.proposal.target == .onto("b"))
    #expect(copied?.operation == .copy)

    let moved = copying.resolve(draggedIDs: ["c"], target: .root, tree: tree, expanded: [])
    #expect(moved?.proposal.isCopyRequested == false)
    #expect(moved?.operation == .move)
  }

  @Test func rejectsRedirectsToInvalidTargets() {
    let result = handler { _ in .redirect(to: .onto("missing"), operation: .move) }
      .resolve(draggedIDs: ["c"], target: .root, tree: tree, expanded: [])
    #expect(result == nil)
  }

  @Test func cachesResolutionsPerDraggedIDsAndTarget() {
    var cache = DropResolutionCache<String>()
    var calls = 0
    let accepting = handler { _ in
      calls += 1
      return .accept(.move)
    }
    func resolve(_ ids: [String], _ target: OutlineDropTarget<String>) -> OutlineDropOperation? {
      cache.resolution(for: ids, target: target) {
        accepting.resolve(draggedIDs: ids, target: target, tree: tree, expanded: [])
      }?.operation
    }

    #expect(resolve(["c"], .onto("a")) == .move)
    #expect(resolve(["c"], .onto("a")) == .move)
    #expect(calls == 1)

    _ = resolve(["c"], .onto("b"))
    _ = resolve(["b", "c"], .onto("a"))
    #expect(calls == 3)

    cache.removeAll()
    _ = resolve(["c"], .onto("a"))
    #expect(calls == 4)
  }

  @Test func cachesCopyRequestsSeparately() {
    var cache = DropResolutionCache<String>()
    let copying = handler { .accept($0.isCopyRequested ? .copy : .move) }
    func resolve(copy: Bool) -> OutlineDropOperation? {
      cache.resolution(for: ["c"], target: .root, isCopyRequested: copy) {
        copying.resolve(
          draggedIDs: ["c"], target: .root, tree: tree, expanded: [], isCopyRequested: copy)
      }?.operation
    }

    #expect(resolve(copy: false) == .move)
    #expect(resolve(copy: true) == .copy)
    #expect(resolve(copy: false) == .move)
  }

  @Test func cachesRejections() {
    var cache = DropResolutionCache<String>()
    var calls = 0
    let rejecting = handler { _ in
      calls += 1
      return .reject
    }
    for _ in 0..<3 {
      let result = cache.resolution(for: ["c"], target: .root) {
        rejecting.resolve(draggedIDs: ["c"], target: .root, tree: tree, expanded: [])
      }
      #expect(result == nil)
    }
    #expect(calls == 1)
  }

  @Test func rejectsTargetsThatNoLongerExistWithoutAskingTheHost() {
    var calls = 0
    let accepting = handler { _ in
      calls += 1
      return .accept(.move)
    }
    #expect(
      accepting.resolve(draggedIDs: ["c"], target: .onto("missing"), tree: tree, expanded: [])
        == nil)
    #expect(
      accepting.resolve(
        draggedIDs: ["c"], target: .insert(into: nil, at: 4), tree: tree, expanded: [])
        == nil)
    #expect(calls == 0)
  }
}
