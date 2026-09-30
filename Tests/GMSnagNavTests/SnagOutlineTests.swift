import SwiftUI
import Testing

@testable import GMSnagNav

/// Checks that the public initializers accept the call shapes promised in the documentation.
@MainActor
@Suite struct SnagOutlineTests {
  @Test func acceptsKeyPathsAndClosuresForChildren() {
    var single: String?
    var multiple: Set<String> = []
    var expansion: Set<String> = []
    let singleBinding = Binding(get: { single }, set: { single = $0 })
    let multipleBinding = Binding(get: { multiple }, set: { multiple = $0 })
    let expansionBinding = Binding(get: { expansion }, set: { expansion = $0 })

    _ = SnagOutline(sampleRoots, children: \.children, selection: singleBinding) { Text($0.id) }
    _ = SnagOutline(
      sampleRoots, children: \.children, selection: multipleBinding, expansion: expansionBinding
    ) { Text($0.id) }
    _ = SnagOutline(sampleRoots, children: { $0.children }, rowContent: { Text($0.id) })
  }

  @Test func selectsEverythingByDefault() {
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
    #expect(sampleRoots.allSatisfy(outline.behavior.canSelect))
  }

  @Test func appliesSelectablePredicate() {
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineSelectable { $0.children == nil }
    #expect(!outline.behavior.canSelect(.group("a")))
    #expect(outline.behavior.canSelect(.leaf("c")))
  }

  @Test func storesPrimaryAction() {
    var activated: Set<String> = []
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlinePrimaryAction { activated = $0 }
    outline.behavior.primaryAction?(["a", "c"])
    #expect(activated == ["a", "c"])
  }

  @Test func storesContextMenu() {
    var requested: Set<String>?
    func menu(for ids: Set<String>) -> Button<Text> {
      requested = ids
      return Button("Delete") {}
    }
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineContextMenu { ids in menu(for: ids) }
    #expect(outline.behavior.contextMenu != nil)
    _ = outline.behavior.contextMenu?(["a2"])
    #expect(requested == ["a2"])
  }

  @Test func appliesAppearanceModifiers() {
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
    #expect(outline.appearance.style == .automatic)
    #expect(outline.appearance.indentation == OutlineAppearance.defaultIndentation)

    let styled = outline.outlineStyle(.plain).outlineIndentation(-5)
    #expect(styled.appearance.style == .plain)
    #expect(styled.appearance.indentation == 0)
  }

  @Test func enablesDraggingExplicitly() {
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
    #expect(outline.behavior.canDrag == nil)

    let draggable = outline.outlineDraggable()
    #expect(draggable.behavior.canDrag?(.leaf("c")) == true)

    let restricted = outline.outlineDraggable { $0.children == nil }
    #expect(restricted.behavior.canDrag?(.group("a")) == false)
  }

  @Test func rejectsDropsIntoOwnSubtreeByDefault() throws {
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .onOutlineDrop { _, _ in true }
    let drop = try #require(outline.behavior.drop)

    let cycle = OutlineDropProposal(
      draggedIDs: ["a"], target: .onto("a2"), isDroppingIntoOwnSubtree: true)
    #expect(drop.validate(cycle) == .reject)

    let move = OutlineDropProposal(draggedIDs: ["c"], target: .onto("a"))
    #expect(drop.validate(move) == .accept(.move))
  }

  @Test func storesCustomDropHandlers() throws {
    var performed: (OutlineDropProposal<String>, OutlineDropOperation)?
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .onOutlineDrop { _ in
        .accept(.copy)
      } perform: { proposal, operation in
        performed = (proposal, operation)
        return true
      }
    let drop = try #require(outline.behavior.drop)
    let proposal = OutlineDropProposal(draggedIDs: ["c"], target: .root)
    #expect(drop.validate(proposal) == .accept(.copy))
    #expect(drop.perform(proposal, .copy))
    #expect(performed?.0 == proposal)
    #expect(performed?.1 == .copy)
  }

  @Test func bindsSelectionModes() {
    var single: String? = "a"
    let outline = SnagOutline(
      sampleRoots, children: \.children, selection: Binding(get: { single }, set: { single = $0 })
    ) { Text($0.id) }

    guard case .single(let binding) = outline.selection else {
      Issue.record("Expected single selection")
      return
    }
    binding.wrappedValue = "c"
    #expect(single == "c")

    let unselectable = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
    guard case .none = unselectable.selection else {
      Issue.record("Expected no selection")
      return
    }
  }
}
