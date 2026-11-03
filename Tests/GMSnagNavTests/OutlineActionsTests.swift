import SwiftUI
import Testing

@testable import GMSnagNav

@MainActor
@Suite struct OutlineActionsTests {
  @MainActor final class Host {
    var roots = sampleRoots
    var pins: Set<String> = []
    var available = true
    var expanded: Set<String> = []
    var result: OutlineDropResult<String>?
    var succeeds = true
    var performed: [(OutlineDropProposal<String>, OutlineDropOperation)] = []
    var completions: [OutlineActionResult<String>] = []

    var actions: OutlineActions<TestItem> {
      OutlineActions(
        data: { self.roots }, children: \.children,
        isPinned: { self.pins.contains($0.id) },
        validate: { self.result ?? .accept($0.isCopyRequested ? .copy : .move) },
        perform: {
          self.performed.append(($0, $1))
          return self.succeeds
        })
    }

    func items(_ ids: Set<String> = ["c"], operation: OutlineDropOperation = .move)
      -> [OutlineMenuItem]
    {
      actions.destinationItems(
        for: ids, operation: operation, expanded: { self.expanded },
        isAvailable: { self.available }, locale: Locale(identifier: "en_US"),
        onCompletion: { self.completions.append($0) }, title: { $0.id })
    }
  }

  let host = Host()

  private func choose(_ item: OutlineMenuItem) {
    if case .action(let perform) = item.kind { perform() } else { Issue.record("Expected action") }
  }

  @Test func buildsRootAndHierarchicalContainersIncludingEmptyOnes() {
    let items = host.items()
    #expect(items.map(\.title) == ["Top Level", "", "a", "b"])
    guard case .menu(let children) = items[2].kind else {
      Issue.record("Expected a submenu for a")
      return
    }
    #expect(children.map(\.title) == ["Move Here", "", "a2"])
    #expect(host.completions.isEmpty)
    #expect(host.performed.isEmpty)
    choose(children[0])
    #expect(host.performed.last?.0.target == .onto("a"))
    #expect(host.performed.last?.0.isTargetExpanded == false)
    choose(items[3])
    #expect(host.performed.last?.0.target == .onto("b"))
  }

  @Test func normalizesSourcesAndPerformsExactlyOnce() {
    choose(host.items(["c", "a1", "a"])[0])
    #expect(host.performed.count == 1)
    #expect(host.performed[0].0.draggedIDs == ["a", "c"])
    #expect(host.completions == [.completed(host.performed[0].0, .move)])
  }

  @Test func aMissingSourceNeverBecomesAPartialTransfer() {
    let items = host.items(["b", "c"])
    host.roots.removeLast()
    choose(items[0])
    #expect(host.performed.isEmpty)
    #expect(host.completions == [.sourceUnavailable])
    let initiallyMissing = host.items(["missing", "b"])
    host.roots.append(.leaf("missing"))
    choose(initiallyMissing[0])
    #expect(host.performed.isEmpty)
    #expect(host.completions.last == .sourceUnavailable)
  }

  @Test(arguments: [OutlineDropOperation.move, .copy])
  func aSelectedDescendantMovedOutAfterOpeningIsStillTransferred(
    operation: OutlineDropOperation
  ) {
    let items = host.items(["a", "a1"], operation: operation)
    host.roots[0].children?.removeFirst()
    host.roots.append(.leaf("a1"))
    choose(items[3])
    #expect(host.performed.count == 1)
    #expect(host.performed.first?.0.draggedIDs == ["a", "a1"])
    #expect(host.performed.first?.1 == operation)
  }

  @Test func aSelectedDescendantRemovedAfterOpeningCancelsTheWholeTransfer() {
    let items = host.items(["a", "a1"])
    host.roots[0].children?.removeFirst()
    choose(items[3])
    #expect(host.performed.isEmpty)
    #expect(host.completions == [.sourceUnavailable])
  }

  @Test func pinsDisableTheEntireSelectionButNotDescendantsCarriedByAnAncestor() {
    host.pins = ["a"]
    let items = host.items(["a", "c"])
    #expect(items[0].isDisabled)
    choose(items[0])
    #expect(host.performed.isEmpty)
    host.pins = ["a1"]
    choose(host.items(["a", "a1"])[0])
    #expect(host.performed.last?.0.draggedIDs == ["a"])
  }

  @Test func aSourcePinnedAfterOpeningIsRejected() {
    let items = host.items()
    host.pins = ["c"]
    choose(items[0])
    #expect(host.performed.isEmpty)
    #expect(host.completions == [.sourceUnavailable])
  }

  @Test func changedRelationshipsBetweenCapturedRootsCancelTheWholeAction() {
    let items = host.items(["a", "b"])
    host.roots = [.group("a", [.group("b")]), .leaf("c")]
    choose(items[0])
    #expect(host.completions == [.sourceUnavailable])
    #expect(host.performed.isEmpty)
  }

  @Test func independentReparentingUsesCurrentDataAndExpansion() {
    let items = host.items(["a1"])
    host.roots = [.group("a", [.group("a2", [.leaf("a1")])]), .group("b"), .leaf("c")]
    host.expanded = ["b"]
    choose(items[3])
    #expect(host.performed.count == 1)
    #expect(host.performed[0].0.isTargetExpanded)
    #expect(host.performed[0].0.draggedIDs == ["a1"])
  }

  @Test func removedOrLeafDestinationsNeverFallBackToRoot() {
    let items = host.items()
    host.roots[1] = .leaf("b")
    choose(items[3])
    #expect(host.completions == [.targetUnavailable])
    host.roots.remove(at: 1)
    choose(items[3])
    #expect(host.completions.last == .targetUnavailable)
    #expect(host.performed.isEmpty)
  }

  @Test func availabilityAndValidationAreReadAgainWhenChosen() {
    let items = host.items()
    host.available = false
    choose(items[0])
    #expect(host.completions == [.unavailable])
    host.available = true
    host.result = .reject
    choose(items[0])
    #expect(host.completions.last == .rejected)
    #expect(host.performed.isEmpty)
  }

  @Test func copiesCannotSilentlyMoveAndMovesCannotCopy() {
    let copy = host.items(operation: .copy)
    host.result = .accept(.move)
    choose(copy[0])
    #expect(host.performed.isEmpty)
    #expect(host.completions == [.rejected])
    let move = host.items()
    host.result = .accept(.copy)
    choose(move[0])
    #expect(host.performed.isEmpty)
    host.result = nil
    choose(copy[0])
    #expect(host.performed.last?.1 == .copy)
    #expect(host.performed.last?.0.isCopyRequested == true)
  }

  @Test func defaultValidatorDisablesCopyDestinations() {
    let actions = OutlineActions(
      data: { sampleRoots }, children: \.children,
      perform: { _, _ in
        Issue.record("Copy must not use the default move performer")
        return true
      })
    #expect(actions.destinationItems(for: ["c"], operation: .copy) { $0.id }[0].isDisabled)
  }

  @Test func redirectsStayInsideTheAdvertisedContainerAndKeepIndices() {
    let items = host.items(["a1"])
    host.result = .redirect(to: .insert(into: "b", at: 0), operation: .move)
    choose(items[0])
    #expect(host.completions == [.rejected])
    choose(items[3])
    #expect(host.performed.last?.0.target == .insert(into: "b", at: 0))
    host.result = .redirect(to: .insert(into: nil, at: 3), operation: .move)
    choose(host.items(["b"])[0])
    #expect(host.performed.last?.0.insertionIndexAfterRemoval == 2)
  }

  @Test func rejectsMoveCyclesEvenIfTheHostAcceptsThem() {
    host.result = .accept(.move)
    let items = host.items(["a"])
    guard case .menu(let children) = items[2].kind else { return }
    #expect(children[0].isDisabled)
    choose(children[0])
    #expect(host.performed.isEmpty)
    #expect(host.completions == [.rejected])
  }

  @Test func theHostDecidesWhatMovingIntoTheCurrentParentMeans() {
    choose(host.items(["b"])[0])
    #expect(host.performed.count == 1)
    #expect(host.performed[0].0.target == .root)
    host.succeeds = false
    choose(host.items(["b"])[0])
    #expect(host.completions.last == .failed)
  }

  @Test func usesTheExplicitLocaleAndHostRootTitle() {
    let items = host.actions.destinationItems(
      for: ["c"], operation: .copy, locale: Locale(identifier: "de_DE")
    ) { $0.id }
    #expect(items[0].title == "Oberste Ebene")
    guard case .menu(let children) = items[2].kind else { return }
    #expect(children[0].title == "Hierher kopieren")
    #expect(
      host.actions.destinationItems(
        for: ["c"], operation: .move, rootTitle: "Library"
      ) { $0.id }[0].title == "Library")
  }

  @Test func theSameValueCanServeDifferentWindowsAndModels() {
    let other = Host()
    other.roots = [.group("other"), .leaf("c")]
    let first = host.items()
    let second = other.items()
    #expect(first.map(\.title) != second.map(\.title))
    host.available = false
    choose(first[0])
    choose(second[0])
    #expect(host.performed.isEmpty)
    #expect(other.performed.count == 1)
  }

  @Test func windowsSharingAnActionValueKeepTheirExpansionAndAvailabilitySeparate() {
    let actions = host.actions
    var available = true
    var secondExpansion: Set<String> = []
    var firstResults: [OutlineActionResult<String>] = []
    var secondResults: [OutlineActionResult<String>] = []
    let first = actions.destinationItems(
      for: ["c"], operation: .move, expanded: { ["a"] }, isAvailable: { available },
      onCompletion: { firstResults.append($0) }, title: { $0.id })
    let second = actions.destinationItems(
      for: ["c"], operation: .move, expanded: { secondExpansion },
      onCompletion: { secondResults.append($0) }, title: { $0.id })
    available = false
    choose(first[0])
    #expect(firstResults == [.unavailable])
    #expect(secondResults.isEmpty)
    guard case .menu(let children) = second[2].kind else { return }
    choose(children[0])
    #expect(host.performed.last?.0.isTargetExpanded == false)
    secondExpansion = ["a"]
    choose(children[0])
    #expect(host.performed.last?.0.isTargetExpanded == true)
    #expect(secondResults.count == 2)
    #expect(firstResults == [.unavailable])
  }

  @Test func menusReleaseTheirModelWhenTheyAreDismissed() {
    weak var weakHost: Host?
    var menu: [OutlineMenuItem]?
    do {
      let owner = Host()
      weakHost = owner
      menu = owner.items()
    }
    #expect(weakHost != nil)
    #expect(menu?.isEmpty == false)
    menu = nil
    #expect(weakHost == nil)
  }

  @Test func theDropOverloadSharesCallbacksAndCanBeOverridden() {
    let configured = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .onOutlineDrop(host.actions)
    #expect(configured.behavior.actionTree?().count == 6)
    #expect(configured.onOutlineDrop { _, _ in true }.behavior.actionTree == nil)
  }
}
