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
      var drop: OutlineDropHandler<String>?
      var springLoading = SpringLoadingBehavior.automatic
      var reportedDuplicates: [Set<String>] = []
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
      behavior.drop = host.drop
      behavior.duplicateIDs = { host.reportedDuplicates.append($0) }
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
          springLoading: host.springLoading,
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

    @Test func reportsRepeatedIdentifiersOncePerChange() {
      update()
      #expect(host.reportedDuplicates.isEmpty)

      host.roots = sampleRoots + [.leaf("a1")]
      update()
      update()
      #expect(host.reportedDuplicates == [["a1"]])
      #expect(visibleIDs == ["a", "b", "c"])

      host.roots = sampleRoots + [.leaf("a1"), .leaf("c")]
      update()
      #expect(host.reportedDuplicates == [["a1"], ["a1", "c"]])
    }

    @Test func sizesRowTextLikeNativeSidebarRows() throws {
      let sizes: [(NSTableView.RowSizeStyle, CGFloat)] = [
        (.small, 11), (.medium, 13), (.large, 15),
      ]
      for (style, size) in sizes {
        outlineView.rowSizeStyle = style
        update()
        let cell = try #require(
          outlineView.view(atColumn: 0, row: 0, makeIfNecessary: true) as? HostingCellView)
        #expect(cell.fontSize == size)
      }
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

    private func acceptAll(
      recording performed: @escaping (OutlineDropProposal<String>, OutlineDropOperation) -> Void = {
        _, _ in
      }
    ) -> OutlineDropHandler<String> {
      OutlineDropHandler(
        validate: { $0.isDroppingIntoOwnSubtree ? .reject : .accept(.move) },
        perform: { proposal, operation in
          performed(proposal, operation)
          return true
        })
    }

    @Test func rejectsDropsWithoutAHandlerOrDraggedElements() {
      update()
      #expect(coordinator.resolveDrop(of: ["c"], onto: nil, childIndex: 0) == nil)

      host.drop = acceptAll()
      update()
      #expect(coordinator.resolveDrop(of: [], onto: nil, childIndex: 0) == nil)
      #expect(coordinator.resolveDrop(of: ["removed"], onto: nil, childIndex: 0) == nil)
    }

    @Test func mapsAppKitPositionsToDropTargets() {
      host.drop = acceptAll()
      host.expansion = ["a"]
      update()
      let onItem = NSOutlineViewDropOnItemIndex

      #expect(
        coordinator.resolveDrop(of: ["c"], onto: item("a"), childIndex: onItem)?.proposal.target
          == .onto("a"))
      #expect(
        coordinator.resolveDrop(of: ["c"], onto: item("a"), childIndex: 1)?.proposal.target
          == .insert(into: "a", at: 1))
      #expect(
        coordinator.resolveDrop(of: ["a1"], onto: nil, childIndex: 3)?.proposal.target
          == .insert(into: nil, at: 3))
      #expect(
        coordinator.resolveDrop(of: ["a1"], onto: nil, childIndex: onItem)?.proposal.target == .root
      )
    }

    @Test func appliesTheHostsValidation() {
      host.drop = acceptAll()
      update()
      // The default policy of the test handler rejects moving a into its own child.
      #expect(coordinator.resolveDrop(of: ["a"], onto: item("a"), childIndex: 0) == nil)
      #expect(
        coordinator.resolveDrop(of: ["c"], onto: item("a"), childIndex: 0)?.operation == .move)
    }

    @Test func asksTheHostOncePerPositionUntilTheDataChanges() {
      var validations = 0
      host.drop = OutlineDropHandler(
        validate: { _ in
          validations += 1
          return .accept(.move)
        }, perform: { _, _ in true })
      update()

      _ = coordinator.resolveDrop(of: ["c"], onto: item("a"), childIndex: 0)
      _ = coordinator.resolveDrop(of: ["c"], onto: item("a"), childIndex: 0)
      #expect(validations == 1)

      _ = coordinator.resolveDrop(of: ["c"], onto: item("a"), childIndex: 1)
      #expect(validations == 2)

      host.expansion = ["a"]
      update()
      _ = coordinator.resolveDrop(of: ["c"], onto: item("a"), childIndex: 0)
      #expect(validations == 3)
    }

    @Test func redirectsToValidTargetsOnly() {
      host.drop = OutlineDropHandler(
        validate: { _ in .redirect(to: .onto("b"), operation: .copy) }, perform: { _, _ in true })
      update()
      let redirected = coordinator.resolveDrop(of: ["c"], onto: nil, childIndex: 0)
      #expect(redirected?.proposal.target == .onto("b"))
      #expect(redirected?.operation == .copy)

      host.drop = OutlineDropHandler(
        validate: { _ in .redirect(to: .insert(into: "b", at: 5), operation: .move) },
        perform: { _, _ in true })
      update()
      #expect(coordinator.resolveDrop(of: ["c"], onto: nil, childIndex: 0) == nil)
    }

    @Test func performsAcceptedDropsWithTheFinalProposal() {
      var performed: (OutlineDropProposal<String>, OutlineDropOperation)?
      host.drop = acceptAll { performed = ($0, $1) }
      update()
      // Moving a (root index 0) below c (root index 3) lands at index 2 after removal.
      #expect(coordinator.performDrop(of: ["a"], onto: nil, childIndex: 3))
      #expect(performed?.0.target == .insert(into: nil, at: 3))
      #expect(performed?.0.insertionIndexAfterRemoval == 2)
      #expect(performed?.1 == .move)

      performed = nil
      #expect(!coordinator.performDrop(of: ["a"], onto: item("a"), childIndex: 0))
      #expect(performed == nil)
    }

    /// Hovers over `id` during a drag and waits for spring-loading to react.
    private func hover(onto id: String?, childIndex: Int = NSOutlineViewDropOnItemIndex) async {
      coordinator.updateSpringLoading(hovering: id.flatMap(item), childIndex: childIndex)
      try? await Task.sleep(for: .milliseconds(250))
    }

    private func isExpanded(_ id: String) -> Bool {
      item(id).map(outlineView.isItemExpanded) ?? false
    }

    @Test func springLoadsCollapsedElementsWithoutChangingTheBinding() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      update()
      await hover(onto: "a")
      #expect(isExpanded("a"))
      #expect(host.expansion.isEmpty)

      // Resting inside the opened element keeps it open.
      await hover(onto: "a2")
      #expect(isExpanded("a") && isExpanded("a2"))
    }

    @Test func closesSpringLoadedElementsWhenThePointerLeaves() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      update()
      await hover(onto: "a")
      await hover(onto: nil, childIndex: 1)
      #expect(!isExpanded("a"))
      #expect(host.expansion.isEmpty)
    }

    @Test func keepsSpringLoadedElementsTheHostExpandedAfterTheDrop() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      update()
      await hover(onto: "a")
      await hover(onto: "a2")
      host.expansion.insert("a")
      coordinator.endSpringLoading()
      #expect(isExpanded("a"))
      #expect(!isExpanded("a2"))
    }

    @Test func doesNotSpringLoadWhenDisabled() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      host.springLoading = .disabled
      update()
      await hover(onto: "a")
      #expect(!isExpanded("a"))
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

    @Test func keepsTheSelectionOfRemovedElementsInTheBinding() {
      host.single = "c"
      update()
      host.roots.removeLast()
      update()
      #expect(outlineView.selectedRowIndexes.isEmpty)
      #expect(host.single == "c")

      host.roots = sampleRoots
      update()
      #expect(outlineView.selectedRowIndexes == [2])
    }

    @Test func keepsRemovedElementsInAMultipleSelection() {
      host.multiple = ["a", "c"]
      update(multipleSelection: true)
      host.roots.removeLast()
      update(multipleSelection: true)
      #expect(outlineView.selectedRowIndexes == [0])
      #expect(host.multiple == ["a", "c"])
    }

    @Test func rejectsDropsOfElementsRemovedDuringTheDrag() {
      host.drop = acceptAll()
      update()
      #expect(coordinator.resolveDrop(of: ["c"], onto: item("b"), childIndex: -1) != nil)

      host.roots.removeLast()
      update()
      #expect(coordinator.resolveDrop(of: ["c"], onto: item("b"), childIndex: -1) == nil)
    }

    @Test func resolvesTheDropAgainstDataChangedDuringTheDrag() {
      var performed: OutlineDropProposal<String>?
      host.drop = acceptAll(recording: { proposal, _ in performed = proposal })
      update()
      // Roots a b c: moving c to the end needs no adjustment.
      #expect(
        coordinator.resolveDrop(of: ["c"], onto: nil, childIndex: 2)?.proposal
          .insertionIndexAfterRemoval == 2)

      // With a removed, c sits at index 1, before the insertion point.
      host.roots.removeFirst()
      update()
      #expect(coordinator.performDrop(of: ["c"], onto: nil, childIndex: 2))
      #expect(performed?.insertionIndexAfterRemoval == 1)
    }

    @Test func ignoresSpringLoadedElementsRemovedDuringTheDrag() async {
      coordinator.springLoadingDelayOverride = .milliseconds(10)
      host.drop = acceptAll()
      update()
      coordinator.updateSpringLoading(hovering: item("a"), childIndex: NSOutlineViewDropOnItemIndex)
      try? await Task.sleep(for: .milliseconds(250))
      #expect(visibleIDs == ["a", "a1", "a2", "b", "c"])

      host.roots.removeFirst()
      update()
      coordinator.endSpringLoading()
      #expect(visibleIDs == ["b", "c"])
      #expect(host.expansion.isEmpty)
    }
  }

#endif
