#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import GMSnagNav

  /// Drives the AppKit coordinator with a real, window-less `NSOutlineView`.
  @MainActor
  @Suite struct OutlineCoordinatorTests {
    /// Mutable state standing in for the host's `@State`.
    final class Host {
      var roots = sampleRoots
      var expansion: Set<String> = []
      var single: String?
      var multiple: Set<String> = []
      var isSelectable: (TestItem) -> Bool = { _ in true }
      var primaryAction: ((Set<String>) -> Void)?
    }

    let host = Host()
    let outlineView = SnagOutlineView()
    let coordinator = OutlineCoordinator<TestItem, Text>()

    init() {
      let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("column"))
      outlineView.addTableColumn(column)
      outlineView.outlineTableColumn = column
      coordinator.attach(to: outlineView)
    }

    private func update(multipleSelection: Bool = false) {
      let host = host
      var behavior = OutlineBehavior<TestItem>()
      behavior.isSelectable = host.isSelectable
      behavior.primaryAction = host.primaryAction
      let selection: OutlineSelection<String> =
        multipleSelection
        ? .multiple(Binding(get: { host.multiple }, set: { host.multiple = $0 }))
        : .single(Binding(get: { host.single }, set: { host.single = $0 }))
      coordinator.update(
        with: AppKitOutlineRenderer(
          tree: OutlineTree(host.roots, children: \.children),
          selection: selection,
          expansion: Binding(get: { host.expansion }, set: { host.expansion = $0 }),
          behavior: behavior,
          rowContent: { Text($0.id) }))
    }

    private var visibleIDs: [String] {
      (0..<outlineView.numberOfRows).compactMap {
        (outlineView.item(atRow: $0) as? NodeBox<String>)?.id
      }
    }

    private func item(_ id: String) -> Any? {
      (0..<outlineView.numberOfRows).lazy.compactMap { outlineView.item(atRow: $0) }
        .first { ($0 as? NodeBox<String>)?.id == id }
    }

    @Test func showsRootsCollapsedByDefault() {
      update()
      #expect(visibleIDs == ["a", "b", "c"])
    }

    @Test func appliesExpansionFromTheBinding() {
      host.expansion = ["a", "a2"]
      update()
      #expect(visibleIDs == ["a", "a1", "a2", "a2x", "b", "c"])

      host.expansion = ["a"]
      update()
      #expect(visibleIDs == ["a", "a1", "a2", "b", "c"])
    }

    @Test func writesUserExpansionIntoTheBinding() {
      update()
      outlineView.expandItem(item("a"))
      #expect(host.expansion == ["a"])

      outlineView.collapseItem(item("a"))
      #expect(host.expansion.isEmpty)
    }

    @Test func restoresChildExpansionWhenTheParentOpens() {
      // a2 is expanded while its parent is collapsed; opening a reveals a2 expanded.
      host.expansion = ["a2"]
      update()
      #expect(visibleIDs == ["a", "b", "c"])

      outlineView.expandItem(item("a"))
      #expect(visibleIDs == ["a", "a1", "a2", "a2x", "b", "c"])
      #expect(host.expansion == ["a", "a2"])
    }

    @Test func showsNoDisclosureForEmptyContainers() throws {
      update()
      let b = try #require(item("b"))
      #expect(!outlineView.isExpandable(b))
      #expect(outlineView.isExpandable(try #require(item("a"))))
    }

    @Test func appliesAndWritesSingleSelection() {
      host.single = "c"
      update()
      #expect(outlineView.selectedRow == 2)

      outlineView.selectRowIndexes([0], byExtendingSelection: false)
      #expect(host.single == "a")
    }

    @Test func appliesAndWritesMultipleSelection() {
      host.multiple = ["a", "c"]
      update(multipleSelection: true)
      #expect(outlineView.allowsMultipleSelection)
      #expect(outlineView.selectedRowIndexes == [0, 2])

      outlineView.selectRowIndexes([1, 2], byExtendingSelection: false)
      #expect(host.multiple == ["b", "c"])
    }

    @Test func filtersUnselectableRows() {
      host.isSelectable = { $0.children == nil }
      update()
      let proposed = coordinator.outlineView(
        outlineView, selectionIndexesForProposedSelection: [0, 2])
      #expect(proposed == [2])
    }

    private func pressReturn() {
      let event = NSEvent.keyEvent(
        with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0,
        context: nil, characters: "\r", charactersIgnoringModifiers: "\r", isARepeat: false,
        keyCode: 36)
      if let event { outlineView.keyDown(with: event) }
    }

    @Test func runsPrimaryActionForTheSelectionOnReturn() {
      var activated: Set<String> = []
      host.primaryAction = { activated = $0 }
      host.single = "c"
      update()
      pressReturn()
      #expect(activated == ["c"])
    }

    @Test func ignoresReturnWithoutSelection() {
      var activated: Set<String>?
      host.primaryAction = { activated = $0 }
      update()
      pressReturn()
      #expect(activated == nil)
    }

    @Test func keepsStateWhenDataChanges() {
      host.expansion = ["a"]
      host.single = "a1"
      update()

      host.roots.append(.leaf("d"))
      update()
      #expect(visibleIDs == ["a", "a1", "a2", "b", "c", "d"])
      #expect(outlineView.selectedRow == 1)
    }

    @Test func dropsSelectionOfRemovedElements() {
      host.single = "c"
      update()
      host.roots.removeLast()
      update()
      #expect(outlineView.selectedRowIndexes.isEmpty)
    }
  }
#endif
