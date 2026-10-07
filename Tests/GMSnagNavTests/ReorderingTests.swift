import SwiftUI
import Testing

@testable import GMSnagNav

@MainActor
@Suite struct ReorderingTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  private func behavior(
    validate: @escaping (OutlineDropProposal<String>) -> OutlineDropResult<String> = { _ in
      .accept(.move)
    },
    perform: @escaping (OutlineDropProposal<String>, OutlineDropOperation) -> Bool = { _, _ in true
    }
  ) -> OutlineBehavior<TestItem> {
    SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineReorderable()
      .onOutlineDrop(validate: validate, perform: perform).behavior
  }

  @Test func movesExactlyOneSiblingWithTheCorrectRemovalAdjustment() {
    let behavior = behavior()
    let up = behavior.reorderingProposal(for: "b", direction: .up, tree: tree, expanded: [])
    #expect(up?.draggedIDs == ["b"])
    #expect(up?.target == .insert(into: nil, at: 0))
    #expect(up?.insertionIndexAfterRemoval == 0)
    let down = behavior.reorderingProposal(for: "b", direction: .down, tree: tree, expanded: [])
    #expect(down?.target == .insert(into: nil, at: 3))
    #expect(down?.insertionIndexAfterRemoval == 2)
    #expect(down?.isCopyRequested == false)
    let nested = behavior.reorderingProposal(
      for: "a1", direction: .down, tree: tree, expanded: ["a"])
    #expect(nested?.target == .insert(into: "a", at: 2))
    #expect(nested?.insertionIndexAfterRemoval == 1)
    #expect(nested?.isTargetExpanded == true)
  }

  @Test func ignoresVisibleDescendantsWhenMovingAContainer() {
    let proposal = behavior().reorderingProposal(
      for: "a", direction: .down, tree: tree, expanded: ["a", "a2"])
    #expect(proposal?.draggedIDs == ["a"])
    #expect(proposal?.target == .insert(into: nil, at: 2))
    #expect(proposal?.insertionIndexAfterRemoval == 1)
  }

  @Test func boundariesMissingRowsAndOnlyChildrenHaveNoAction() {
    var calls = 0
    let behavior = behavior(validate: { _ in
      calls += 1
      return .accept(.move)
    })
    #expect(behavior.reorderingProposal(for: "a", direction: .up, tree: tree, expanded: []) == nil)
    #expect(
      behavior.reorderingProposal(for: "c", direction: .down, tree: tree, expanded: []) == nil)
    #expect(
      behavior.reorderingProposal(for: "missing", direction: .up, tree: tree, expanded: []) == nil)
    #expect(
      behavior.reorderingProposal(for: "a2x", direction: .down, tree: tree, expanded: []) == nil)
    #expect(calls == 0)
  }

  @Test func requiresOptInAHandlerAndAnEligibleElement() {
    var disabled = behavior()
    disabled.canReorder = nil
    #expect(!disabled.reorder("b", direction: .up, tree: tree, expanded: []))
    disabled.canReorder = { _ in false }
    #expect(!disabled.reorder("b", direction: .up, tree: tree, expanded: []))
    disabled.canReorder = { _ in true }
    disabled.drop = nil
    #expect(!disabled.reorder("b", direction: .up, tree: tree, expanded: []))
  }

  @Test func rejectionCopyAndRedirectsCannotPerformAnotherAction() {
    for result: OutlineDropResult<String> in [
      .reject, .accept(.copy), .redirect(to: .onto("a"), operation: .move),
      .redirect(to: .insert(into: nil, at: 1), operation: .move),
      .redirect(to: .insert(into: nil, at: 0), operation: .move),
      .redirect(to: .onto("missing"), operation: .move),
    ] {
      var performed = false
      let behavior = behavior(
        validate: { _ in result },
        perform: { _, _ in
          performed = true
          return true
        })
      #expect(!behavior.reorder("b", direction: .down, tree: tree, expanded: []))
      #expect(!performed)
    }
  }

  @Test func equivalentRedirectStillUsesTheHostsPerformer() {
    var received: OutlineDropProposal<String>?
    let behavior = behavior(
      validate: { _ in .redirect(to: .insert(into: nil, at: 3), operation: .move) },
      perform: { proposal, operation in
        received = proposal
        #expect(operation == .move)
        return true
      })
    #expect(behavior.reorder("b", direction: .down, tree: tree, expanded: []))
    #expect(received?.insertionIndexAfterRemoval == 2)
  }

  @Test func revalidatesAnAdvertisedActionAndPropagatesFailure() {
    var allowed = true
    var performed = false
    let behavior = behavior(
      validate: { _ in allowed ? .accept(.move) : .reject },
      perform: { _, _ in
        performed = true
        return false
      })
    #expect(
      behavior.reorderingProposal(for: "b", direction: .down, tree: tree, expanded: []) != nil)
    allowed = false
    #expect(!behavior.reorder("b", direction: .down, tree: tree, expanded: []))
    #expect(!performed)
    allowed = true
    #expect(!behavior.reorder("b", direction: .down, tree: tree, expanded: []))
    #expect(performed)
  }

  @Test func leavesAnActiveRenameAlone() {
    var behavior = behavior()
    behavior.renaming = OutlineRenameHandler(
      renaming: .constant("a1"), canRename: { _ in true }, onRename: { _, _ in })
    #expect(!behavior.reorder("b", direction: .up, tree: tree, expanded: []))
  }
}
