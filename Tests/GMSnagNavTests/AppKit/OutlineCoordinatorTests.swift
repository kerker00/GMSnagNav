#if os(macOS)
  import AppKit
  import Foundation
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
      var appearance = OutlineAppearance()
      var canDrag: ((TestItem) -> Bool)?
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
      behavior.canDrag = host.canDrag
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
          appearance: host.appearance,
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

    @Test func appliesStyleAndIndentation() {
      update()
      #expect(outlineView.style == .sourceList)
      #expect(outlineView.indentationPerLevel == OutlineAppearance.defaultIndentation)

      host.appearance.style = .plain
      host.appearance.indentation = 24
      update()
      #expect(outlineView.style == .plain)
      #expect(outlineView.indentationPerLevel == 24)
    }

    @Test func runsAppKitConfigurationAfterEveryUpdate() {
      var calls = 0
      host.appearance.appKitConfiguration = { outlineView in
        calls += 1
        outlineView.rowSizeStyle = .large
      }
      update()
      update()
      #expect(calls == 2)
      #expect(outlineView.rowSizeStyle == .large)
    }

    private func writer(for id: String) -> NSPasteboardWriting? {
      item(id).flatMap { coordinator.outlineView(outlineView, pasteboardWriterForItem: $0) }
    }

    @Test func startsNoDragsUnlessDraggingIsEnabled() {
      update()
      #expect(writer(for: "a") == nil)
    }

    @Test func dragsOnlyDraggableElements() {
      host.canDrag = { $0.id != "b" }
      update()
      #expect(writer(for: "a") != nil)
      #expect(writer(for: "b") == nil)
    }

    @Test func resolvesDraggedElementsFromTokensOnThePasteboard() {
      host.canDrag = { _ in true }
      update()
      let writers = ["c", "a"].compactMap(writer(for:))
      #expect(writers.count == 2)
      let pasteboard = NSPasteboard(name: NSPasteboard.Name("GMSnagNavTests-\(UUID().uuidString)"))
      defer { pasteboard.releaseGlobally() }
      pasteboard.clearContents()
      pasteboard.writeObjects(writers)
      #expect(coordinator.draggedIDs(on: pasteboard) == ["c", "a"])
    }

    @Test func ignoresForeignPasteboardContent() {
      update()
      let pasteboard = NSPasteboard(name: NSPasteboard.Name("GMSnagNavTests-\(UUID().uuidString)"))
      defer { pasteboard.releaseGlobally() }
      pasteboard.clearContents()
      let foreign = NSPasteboardItem()
      foreign.setString("not-a-token", forType: OutlineCoordinator<TestItem, Text>.draggedRowType)
      pasteboard.writeObjects([foreign])
      #expect(coordinator.draggedIDs(on: pasteboard).isEmpty)
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

    @Test func keepsAMovedGroupExpanded() {
      host.roots = [.group("a", [.group("f", [.leaf("f1")])]), .group("b", [.leaf("b1")])]
      host.expansion = ["a", "b", "f"]
      update()
      #expect(visibleIDs == ["a", "f", "f1", "b", "b1"])

      host.roots = [.group("a"), .group("b", [.leaf("b1"), .group("f", [.leaf("f1")])])]
      update()
      #expect(visibleIDs == ["a", "b", "b1", "f", "f1"])
    }

    @Test func updatesRowContentInPlace() throws {
      host.roots = [.leaf("x")]
      update()
      let before = try #require(item("x") as? NodeBox<String>)

      host.roots = [.leaf("x"), .leaf("y")]
      update()
      // The same item object is kept, so AppKit keeps its row state.
      #expect((item("x") as? NodeBox<String>) === before)
    }

    @Test(arguments: 0..<150)
    func matchesVisibleRowsAfterRandomEdits(seed: Int) {
      var random = SeededRandom(seed: UInt64(seed) &+ 7)
      host.roots = RandomTree.make(using: &random)
      let ids = RandomTree.allIDs(host.roots)
      host.expansion = Set(ids.filter { _ in random.next() % 2 == 0 })
      update()

      for _ in 0..<3 {
        host.roots = RandomTree.edit(host.roots, using: &random)
        update()
        let expected = OutlineTree(host.roots, children: \.children)
          .visibleRows(expanded: host.expansion).map(\.id)
        #expect(visibleIDs == expected, "seed \(seed)")
      }
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
