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
      var canReorder: ((TestItem) -> Bool)?
      var drop: OutlineDropHandler<String>?
      var springLoading = SpringLoadingBehavior.automatic
      var reportedDuplicates: [Set<String>] = []
      var typeSelectText: ((TestItem) -> String?)?
      var sectionTitle: ((TestItem) -> String?)?
      var renaming: String?
      var canRename: ((TestItem) -> Bool)?
      var revealsSelection = true
      var contextMenu: ((Set<String>) -> AnyView)?
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
      behavior.canReorder = host.canReorder
      behavior.drop = host.drop
      behavior.duplicateIDs = { host.reportedDuplicates.append($0) }
      behavior.typeSelectText = host.typeSelectText
      behavior.sectionTitle = host.sectionTitle
      behavior.revealsSelection = host.revealsSelection
      behavior.contextMenu = host.contextMenu
      if let canRename = host.canRename {
        behavior.renaming = OutlineRenameHandler(
          renaming: Binding(get: { host.renaming }, set: { host.renaming = $0 }),
          canRename: canRename, onRename: { _, _ in })
      }
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

    @Test func commandOptionArrowsReorderAndKeepTheSameSelection() throws {
      host.canReorder = { _ in true }
      host.single = "b"
      host.drop = OutlineDropHandler(
        validate: { _ in .accept(.move) },
        perform: { [host] proposal, _ in
          guard let id = proposal.draggedIDs.first,
            let source = host.roots.firstIndex(where: { $0.id == id }),
            let destination = proposal.insertionIndexAfterRemoval
          else { return false }
          let item = host.roots.remove(at: source)
          host.roots.insert(item, at: destination)
          return true
        })
      update()
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 320, height: 480),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      window.contentView = outlineView
      #expect(window.makeFirstResponder(outlineView))
      let down = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero,
          modifierFlags: [.command, .option], timestamp: 0, windowNumber: window.windowNumber,
          context: nil, characters: "\u{F701}", charactersIgnoringModifiers: "\u{F701}",
          isARepeat: false, keyCode: 125))
      #expect(window.performKeyEquivalent(with: down))
      #expect(host.roots.map(\.id) == ["a", "c", "b"])
      update()
      #expect(host.single == "b")
      #expect(visibleIDs == ["a", "c", "b"])
      #expect(window.firstResponder === outlineView)
      #expect(!coordinator.canReorder("b", direction: .down))
      let field = NSTextField(string: "Editing")
      outlineView.addSubview(field)
      #expect(window.makeFirstResponder(field))
      var called = false
      outlineView.onReorder = { _ in
        called = true
        return true
      }
      #expect(!outlineView.performKeyEquivalent(with: down))
      #expect(!called)
    }

    @Test func reorderCommandsIgnoreMultipleAndHiddenSelections() {
      host.canReorder = { _ in true }
      var performed = false
      host.drop = OutlineDropHandler(
        validate: { _ in .accept(.move) },
        perform: { _, _ in
          performed = true
          return true
        })
      host.multiple = ["b", "c"]
      update(multipleSelection: true)
      #expect(!coordinator.reorderSelection(.up))
      host.single = "a2"
      update()
      #expect(!coordinator.reorderSelection(.up))
      #expect(!performed)
    }

    @Test func unavailableReorderShortcutsDoNotFallThroughToNativeNavigation() throws {
      host.canReorder = { _ in false }
      host.single = "b"
      host.drop = OutlineDropHandler(
        validate: { _ in .accept(.move) },
        perform: { _, _ in
          Issue.record("Disabled move performed")
          return true
        })
      update()
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 320, height: 480),
        styleMask: [.titled], backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      window.contentView = outlineView
      #expect(window.makeFirstResponder(outlineView))
      let up = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero,
          modifierFlags: [.command, .option], timestamp: 0, windowNumber: window.windowNumber,
          context: nil, characters: "\u{F700}", charactersIgnoringModifiers: "\u{F700}",
          isARepeat: false, keyCode: 126))
      #expect(window.performKeyEquivalent(with: up))
      #expect(host.single == "b")
      #expect(visibleIDs == ["a", "b", "c"])
      host.canReorder = nil
      update()
      #expect(!outlineView.performKeyEquivalent(with: up))
    }

    private func item(_ id: String) -> Any? {
      (0..<outlineView.numberOfRows).lazy.compactMap { outlineView.item(atRow: $0) }
        .first { ($0 as? NodeBox<String>)?.id == id }
    }

    @Test func providesTheHostsTextForTypeSelect() {
      update()
      #expect(coordinator.typeSelectText(for: "c") == nil)

      host.typeSelectText = { $0.id.uppercased() }
      host.isSelectable = { $0.children == nil }
      update()
      #expect(coordinator.typeSelectText(for: "c") == "C")
      // Rows that cannot be selected are skipped, as are unknown elements.
      #expect(coordinator.typeSelectText(for: "a") == nil)
      #expect(coordinator.typeSelectText(for: "missing") == nil)
      #expect(
        coordinator.outlineView(outlineView, typeSelectStringFor: nil, item: item("c")!) == "C")
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

    @Test func reindentsVisibleRowsWhenTheIndentationChanges() throws {
      host.expansion = ["a"]
      host.single = "a1"
      host.appearance.indentation = 14
      update()
      outlineView.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
      outlineView.layoutSubtreeIfNeeded()
      let before = try #require(outlineView.view(atColumn: 0, row: 1, makeIfNecessary: true))
        .frame.minX

      host.appearance.indentation = 30
      update()
      outlineView.layoutSubtreeIfNeeded()
      let after = try #require(outlineView.view(atColumn: 0, row: 1, makeIfNecessary: true))
      #expect(after.frame.minX == before + 16)
      #expect(outlineView.selectedRowIndexes == [1])
    }

    @Test func reindentsDisclosureTrianglesAlongWithDataChanges() {
      host.expansion = ["a"]
      host.appearance.indentation = 14
      update()
      outlineView.frame = CGRect(x: 0, y: 0, width: 300, height: 400)
      outlineView.layoutSubtreeIfNeeded()
      // Row 2 is a2, an expandable child of a.
      func triangleX() -> CGFloat? {
        outlineView.rowView(atRow: 2, makeIfNecessary: false)?.subviews
          .first { $0.identifier == NSOutlineView.disclosureButtonIdentifier }?.frame.minX
      }
      let before = triangleX()

      host.appearance.indentation = 30
      host.roots.removeLast()
      update()
      outlineView.layoutSubtreeIfNeeded()
      #expect(before != nil)
      #expect(triangleX() == before.map { $0 + 16 })
      #expect(visibleIDs == ["a", "a1", "a2", "b"])
    }

    @Test func keepsTheIndentationWhenTheConfigurationChangesTheRowSize() {
      host.appearance.indentation = 30
      host.appearance.appKitConfiguration = { $0.rowSizeStyle = .large }
      update()
      #expect(outlineView.rowSizeStyle == .large)
      #expect(outlineView.indentationPerLevel == 30)
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
      let a = try #require(item("a"))
      let b = try #require(item("b"))
      #expect(!outlineView.isExpandable(b))
      #expect(outlineView.isExpandable(a))
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

    @Test func showsSectionsAsUnselectableGroupRows() {
      host.sectionTitle = { $0.id == "a" ? "A" : nil }
      host.expansion = ["a"]
      update()
      #expect(coordinator.outlineView(outlineView, isGroupItem: item("a")!))
      #expect(!coordinator.outlineView(outlineView, isGroupItem: item("a1")!))
      // Rows: a, a1, a2, b, c.
      let proposed = coordinator.outlineView(
        outlineView, selectionIndexesForProposedSelection: [0, 1])
      #expect(proposed == [1])
    }

    @Test func renamesTheSelectedRowOnReturnLikeTheFinder() {
      var activated: Set<String>?
      host.primaryAction = { activated = $0 }
      host.canRename = { $0.id != "a" }
      host.single = "c"
      update()
      #expect(coordinator.handleReturn())
      #expect(host.renaming == "c")
      #expect(activated == nil)

      // Rows that cannot be renamed keep running the primary action.
      host.renaming = nil
      host.single = "a"
      update()
      #expect(coordinator.handleReturn())
      #expect(host.renaming == nil)
      #expect(activated == ["a"])
    }

    @Test func restartsAPendingRenameOnReturn() async throws {
      host.canRename = { _ in true }
      host.single = "c"
      host.renaming = "c"
      update()
      #expect(coordinator.handleReturn())
      #expect(host.renaming == nil)
      try await Task.sleep(for: .milliseconds(200))
      let deadline = ContinuousClock.now + .seconds(2)
      while host.renaming != "c", ContinuousClock.now < deadline {
        try await Task.sleep(for: .milliseconds(10))
      }
      #expect(host.renaming == "c")
    }

    @Test func runsThePrimaryActionOnReturnForSeveralSelectedRows() {
      var activated: Set<String>?
      host.primaryAction = { activated = $0 }
      host.canRename = { _ in true }
      host.multiple = ["a", "c"]
      update(multipleSelection: true)
      #expect(coordinator.handleReturn())
      #expect(host.renaming == nil)
      #expect(activated == ["a", "c"])
    }

    /// Lets the tasks the coordinator scheduled for after an update run.
    private func settle() async {
      for _ in 0..<5 { await Task.yield() }
    }

    @Test func revealsElementsTheHostSelects() async {
      update()
      host.single = "a2x"
      update()
      await settle()
      #expect(host.expansion == ["a", "a2"])
      update()
      #expect(visibleIDs.contains("a2x"))
      #expect(outlineView.selectedRow == outlineView.row(forItem: item("a2x")))
    }

    @Test func leavesTheExpansionAloneWhenRevealingIsOff() async {
      host.revealsSelection = false
      update()
      host.single = "a2x"
      update()
      await settle()
      #expect(host.expansion.isEmpty)
    }

    @Test func doesNotRevealWhatTheUserSelects() async {
      host.expansion = ["a"]
      update()
      outlineView.selectRowIndexes([1], byExtendingSelection: false)
      #expect(host.single == "a1")
      // The user collapses the container while its child stays selected.
      host.expansion = []
      update()
      await settle()
      #expect(host.expansion.isEmpty)
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

    @Test(arguments: [("o", UInt16(31)), ("\u{F701}", UInt16(125))])
    func opensTheSelectionWithCommandWithoutRenaming(key: String, keyCode: UInt16) throws {
      var activated: Set<String>?
      host.primaryAction = { activated = $0 }
      host.canRename = { _ in true }
      host.single = "c"
      update()
      let event = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
          windowNumber: 0, context: nil, characters: key, charactersIgnoringModifiers: key,
          isARepeat: false, keyCode: keyCode))
      outlineView.keyDown(with: event)
      #expect(activated == ["c"])
      #expect(host.renaming == nil)
    }

    @Test func primaryActionIgnoresASelectionFilteredOutOfTheTree() {
      var activated = false
      host.primaryAction = { _ in activated = true }
      host.single = "missing"
      update()
      #expect(!coordinator.handlePrimaryAction())
      #expect(!activated)
    }

    @Test func commandKeyEquivalentRequiresTheOutlinesFocus() throws {
      var activated = 0
      host.primaryAction = { _ in activated += 1 }
      host.single = "c"
      update()
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 320, height: 480), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      let scrollView = NSScrollView(frame: window.contentView!.bounds)
      scrollView.documentView = outlineView
      window.contentView = scrollView
      defer { window.close() }
      let commandO = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: "o",
          charactersIgnoringModifiers: "o", isARepeat: false, keyCode: 31))
      #expect(window.makeFirstResponder(outlineView))
      #expect(window.performKeyEquivalent(with: commandO))
      #expect(activated == 1)
      window.makeFirstResponder(nil)
      #expect(!outlineView.performKeyEquivalent(with: commandO))
      #expect(activated == 1)
    }

    @Test(arguments: [("o", UInt16(31)), ("\u{F701}", UInt16(125))])
    func commandKeyEquivalentHandlesHostedRowFocusButLeavesTextEditingAlone(
      key: String, keyCode: UInt16
    ) throws {
      var activated = 0
      host.primaryAction = { _ in activated += 1 }
      host.single = "c"
      update()
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 320, height: 480), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = outlineView
      defer { window.close() }
      let row = NSHostingView(rootView: Text("Hosted row").focusable())
      row.frame = CGRect(x: 0, y: 0, width: 300, height: 30)
      outlineView.addSubview(row)
      window.contentView?.layoutSubtreeIfNeeded()
      let commandO = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: key,
          charactersIgnoringModifiers: key, isARepeat: false, keyCode: keyCode))
      #expect(window.makeFirstResponder(row))
      #expect(window.firstResponder === row)
      #expect(window.performKeyEquivalent(with: commandO))
      #expect(activated == 1)
      let field = NSTextField(string: "Rename")
      outlineView.addSubview(field)
      #expect(window.makeFirstResponder(field))
      #expect(!outlineView.performKeyEquivalent(with: commandO))
      #expect(activated == 1)
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
      let writers = ["c", "a"].compactMap { writer(for: $0) as? NSPasteboardItem }
      #expect(writers.count == 2)
      #expect(coordinator.draggedIDs(in: writers) == ["c", "a"])
    }

    @Test func ignoresForeignPasteboardContent() {
      update()
      let foreign = NSPasteboardItem()
      foreign.setString("not-a-token", forType: OutlineCoordinator<TestItem, Text>.draggedRowType)
      #expect(coordinator.draggedIDs(in: [foreign]).isEmpty)
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

    @Test func performsCopiesWhenTheUserAsksForThem() {
      var performed: (OutlineDropProposal<String>, OutlineDropOperation)?
      host.drop = OutlineDropHandler(
        validate: { .accept($0.isCopyRequested ? .copy : .move) },
        perform: { proposal, operation in
          performed = (proposal, operation)
          return true
        })
      update()
      #expect(coordinator.performDrop(of: ["c"], onto: item("a"), childIndex: 0, copying: true))
      #expect(performed?.0.isCopyRequested == true)
      #expect(performed?.1 == .copy)
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
      await coordinator.springLoadingSettled()
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
      // Group rows make AppKit load rows while it starts an update; cover them as well.
      if seed % 2 == 0 {
        host.sectionTitle = { $0.children != nil ? $0.id : nil }
      }
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
      await hover(onto: "a")
      #expect(visibleIDs == ["a", "a1", "a2", "b", "c"])

      host.roots.removeFirst()
      update()
      coordinator.endSpringLoading()
      #expect(visibleIDs == ["b", "c"])
      #expect(host.expansion.isEmpty)
    }

    // MARK: Clicks

    @Test func clickingASelectableRowTakesFocusFromTheDetailAndEnablesKeyboardNavigation() throws {
      host.single = "b"
      var activated: Set<String> = []
      host.primaryAction = { activated = $0 }
      update()
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      let root = try #require(window.contentView)
      outlineView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
      root.addSubview(outlineView)
      let detailField = NSTextField(string: "Detail name")
      detailField.frame = CGRect(x: 330, y: 100, width: 260, height: 30)
      root.addSubview(detailField)
      #expect(window.makeFirstResponder(detailField))
      coordinator.handleClick(onRow: 1, at: nil)
      #expect(window.firstResponder === outlineView)
      let down = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: "\u{F701}",
          charactersIgnoringModifiers: "\u{F701}", isARepeat: false, keyCode: 125))
      window.firstResponder?.keyDown(with: down)
      #expect(host.single == "c")
      update()
      #expect(window.firstResponder === outlineView)
      let commandO = try #require(
        NSEvent.keyEvent(
          with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
          windowNumber: window.windowNumber, context: nil, characters: "o",
          charactersIgnoringModifiers: "o", isARepeat: false, keyCode: 31))
      #expect(window.performKeyEquivalent(with: commandO))
      #expect(activated == ["c"])
    }

    @Test func rowFocusChangesLeaveInlineEditorsAndUnrelatedDetailEditsAlone() throws {
      host.single = "c"
      host.canRename = { _ in true }
      host.renaming = "c"
      update()
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 640, height: 480), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      defer { window.close() }
      let root = try #require(window.contentView)
      outlineView.frame = CGRect(x: 0, y: 0, width: 320, height: 480)
      root.addSubview(outlineView)
      let renameField = NSTextField(string: "Inline name")
      renameField.frame = CGRect(x: 40, y: 100, width: 260, height: 30)
      outlineView.addSubview(renameField)
      #expect(window.makeFirstResponder(renameField))
      let editor = window.firstResponder
      coordinator.handleClick(onRow: 2, at: nil)
      #expect(window.firstResponder === editor)
      update()
      #expect(window.firstResponder === editor)
      host.renaming = nil
      let detailField = NSTextField(string: "Detail name")
      detailField.frame = CGRect(x: 330, y: 100, width: 260, height: 30)
      root.addSubview(detailField)
      #expect(window.makeFirstResponder(detailField))
      let detailEditor = window.firstResponder
      host.single = "b"
      update()
      #expect(window.firstResponder === detailEditor)
      coordinator.handleClick(onRow: -1, at: nil)
      #expect(window.firstResponder === detailEditor)
    }

    @Test func clickingAnUnselectableContainerTogglesIt() {
      host.isSelectable = { $0.children == nil }
      update()
      coordinator.handleClick(onRow: 0, at: nil)
      #expect(host.expansion == ["a"])
      coordinator.handleClick(onRow: 0, at: nil)
      #expect(host.expansion.isEmpty)
    }

    @Test func clickingASelectableRowOrNoRowDoesNotToggle() {
      host.isSelectable = { $0.id != "a" }
      update()
      coordinator.handleClick(onRow: 2, at: nil)  // c, selectable
      coordinator.handleClick(onRow: -1, at: nil)
      #expect(host.expansion.isEmpty)
    }

    @Test func clickingTheDisclosureTriangleIsLeftToAppKit() {
      host.isSelectable = { $0.children == nil }
      update()
      let triangle = outlineView.frameOfOutlineCell(atRow: 0)
      coordinator.handleClick(onRow: 0, at: CGPoint(x: triangle.midX, y: triangle.midY))
      #expect(host.expansion.isEmpty)
    }

    @Test func togglesAfterTheDoubleClickIntervalWithAPrimaryAction() async {
      host.isSelectable = { $0.children == nil }
      host.primaryAction = { _ in }
      update()
      coordinator.doubleClickDelayOverride = .milliseconds(10)
      coordinator.handleClick(onRow: 0, at: nil)
      #expect(host.expansion.isEmpty)
      await coordinator.pendingToggleSettled()
      #expect(host.expansion == ["a"])
    }

    @Test func doubleClickingRunsThePrimaryActionInsteadOfToggling() async {
      var activated: Set<String>?
      host.isSelectable = { $0.children == nil }
      host.primaryAction = { activated = $0 }
      update()
      coordinator.doubleClickDelayOverride = .seconds(10)
      coordinator.handleClick(onRow: 0, at: nil)
      coordinator.handleDoubleClick(onRow: 0)
      await coordinator.pendingToggleSettled()
      #expect(activated == ["a"])
      #expect(host.expansion.isEmpty)

      coordinator.handleDoubleClick(onRow: -1)
      #expect(activated == ["a"])
    }

    @Test func forwardsClicksFromTheClickTarget() {
      let target = OutlineClickTarget()
      var clicks: [String] = []
      target.onClick = { clicks.append("click") }
      target.onDoubleClick = { clicks.append("double") }
      target.click(nil)
      target.doubleClick(nil)
      #expect(clicks == ["click", "double"])
    }

    // MARK: Dragging details

    @Test func forgetsTheDragTokensWhenTheDragEnds() throws {
      host.canDrag = { _ in true }
      update()
      let row = try #require(item("c"))
      let writer = try #require(
        coordinator.outlineView(outlineView, pasteboardWriterForItem: row) as? NSPasteboardItem)
      #expect(coordinator.draggedIDs(in: [writer]) == ["c"])
      coordinator.endDrag()
      #expect(coordinator.draggedIDs(in: [writer]).isEmpty)
    }

    @Test func treatsAnOptionLimitedMaskAsACopyRequest() {
      typealias Coordinator = OutlineCoordinator<TestItem, Text>
      #expect(Coordinator.isCopyRequested(mask: [.copy]))
      #expect(!Coordinator.isCopyRequested(mask: [.copy, .move]))
      #expect(!Coordinator.isCopyRequested(mask: [.move]))
      #expect(OutlineDropOperation.move.dragOperation == .move)
      #expect(OutlineDropOperation.copy.dragOperation == .copy)
    }

    @Test func followsTheSystemsSpringLoadingPreferences() throws {
      let defaults = try #require(UserDefaults(suiteName: "GMSnagNavTests.\(UUID())"))
      coordinator.systemDefaults = defaults
      update()
      #expect(coordinator.springLoadingDelay == .seconds(0.5))

      defaults.set(0.8, forKey: "com.apple.springing.delay")
      #expect(coordinator.springLoadingDelay == .seconds(0.8))

      defaults.set(false, forKey: "com.apple.springing.enabled")
      #expect(coordinator.springLoadingDelay == nil)

      host.springLoading = .enabled
      update()
      #expect(coordinator.springLoadingDelay == .seconds(0.8))

      host.springLoading = .disabled
      update()
      #expect(coordinator.springLoadingDelay == nil)
    }

    // MARK: Updates

    @Test func acceptsUpdatesBeforeItIsAttached() {
      let detached = OutlineCoordinator<TestItem, Text>()
      detached.update(
        with: AppKitOutlineRenderer(
          tree: OutlineTree(sampleRoots, children: \.children), selection: .none,
          expansion: .constant([]), behavior: OutlineBehavior(), appearance: OutlineAppearance(),
          rowContent: { Text($0.id) }))
      #expect(detached.outlineView == nil)
    }

    @Test func reloadsInsteadOfAnimatingVeryLargeChanges() {
      host.roots = (0..<300).map { .leaf("old\($0)") }
      update()
      host.roots = (0..<300).map { .leaf("new\($0)") }
      update()
      #expect(visibleIDs == host.roots.map(\.id))
    }

    @Test func attachesTheContextMenuToRows() {
      host.contextMenu = { _ in AnyView(Button("Delete") {}) }
      update()
      let cell = coordinator.outlineView(outlineView, viewFor: nil, item: item("c")!)
      #expect(cell is HostingCellView)
    }
  }

#endif
