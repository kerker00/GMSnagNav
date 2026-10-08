import XCTest

/// Drives the real demo app: selection, and on macOS genuine mouse drags.
///
/// The app starts with `-ui-testing`, which resets its settings, so every test sees the sample
/// library with the top-level folders expanded.
@MainActor
final class SidebarUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    #if os(macOS)
      // SwiftUI may relaunch without a window when the previous run closed it; open a new one.
      if !app.windows.firstMatch.waitForExistence(timeout: 3) {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), "No window opened")
      }
    #endif
  }

  // MARK: Helpers

  /// Skips tests that keep using the sidebar after selecting a row. On iPhone, the split view is
  /// collapsed: selecting a row replaces the sidebar with the detail view, and there is no
  /// hardware keyboard to drive the outline with.
  private func requireSidebarBesideDetail() throws {
    #if os(iOS)
      if UIDevice.current.userInterfaceIdiom == .phone {
        throw XCTSkip("The split view is collapsed on iPhone.")
      }
    #endif
  }

  private func row(_ name: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "sidebar-row-\(name)").firstMatch
  }

  /// The location shown in the detail view, such as "Archive › Inbox".
  private var detailLocation: String {
    let element = app.descendants(matching: .any).matching(identifier: "detail-location").firstMatch
    XCTAssertTrue(element.waitForExistence(timeout: 5), "The detail view shows no location")
    let text = (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    // On iOS, the form row combines its label and value into one element: "Location, Inbox".
    let prefix = "Location, "
    return text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
  }

  /// Waits until the detail view shows `expected`; the view may still show the previous
  /// selection right after a click.
  private func assertDetailLocation(
    _ expected: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    let deadline = Date().addingTimeInterval(5)
    var location = detailLocation
    while location != expected, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
      location = detailLocation
    }
    XCTAssertEqual(location, expected, file: file, line: line)
  }

  private func select(_ name: String) {
    let row = row(name)
    XCTAssertTrue(row.waitForExistence(timeout: 5), "No row named \(name)")
    #if os(macOS)
      row.click()
    #else
      row.tap()
    #endif
  }

  // MARK: Selection

  func testSelectingADocumentShowsItsDetails() {
    select("Inbox")
    assertDetailLocation("Inbox")
  }

  func testSelectingANestedDocumentShowsItsPath() {
    select("Weekly Report")
    assertDetailLocation("Work › Weekly Report")
  }

  // MARK: Keyboard and accessibility

  func testShowInSidebarClearsSearchAndRevealsTheSelectedNestedDocument() throws {
    search("Contract")
    select("Contract")
    assertDetailLocation("Work › Clients › Globex › Contract")
    #if os(iOS)
      if app.navigationBars.buttons["Library"].exists {
        throw XCTSkip(
          "Selection is cleared on return in a collapsed split view; tested separately.")
      }
    #endif
    let show = app.buttons["detail-show-in-sidebar"]
    XCTAssertTrue(show.waitForExistence(timeout: 5))
    #if os(macOS)
      show.click()
    #else
      show.tap()
    #endif
    XCTAssertTrue(row("Inbox").waitForExistence(timeout: 5), "Search was not cleared")
    XCTAssertTrue(row("Contract").waitForExistence(timeout: 5), "Ancestors were not expanded")
    XCTAssertTrue(row("Contract").isHittable)
    assertDetailLocation("Work › Clients › Globex › Contract")
    app.typeKey(.downArrow, modifierFlags: [])
    assertDetailLocation("Work › Internal")
  }

  func testShowInSidebarRestoresKeyboardFocusForAnAlreadySelectedDocument() throws {
    select("Inbox")
    let show = app.buttons["detail-show-in-sidebar"]
    XCTAssertTrue(show.waitForExistence(timeout: 5))
    #if os(iOS)
      // Only once the detail view is shown, the back button tells whether the split view is
      // collapsed; right after the tap, the navigation may still be on its way.
      if app.navigationBars.buttons["Library"].exists {
        throw XCTSkip(
          "Selection is cleared on return in a collapsed split view; tested separately.")
      }
    #endif
    for _ in 0..<2 {
      #if os(macOS)
        show.click()
      #else
        show.tap()
      #endif
      assertDetailLocation("Inbox")
    }
    app.typeKey(.downArrow, modifierFlags: [])
    assertDetailLocation("Ideas")
  }

  #if os(iOS)
    func testShowInSidebarReturnsToACollapsedSidebarAndAllowsReopening() throws {
      select("Inbox")
      guard app.navigationBars.buttons["Library"].exists else {
        throw XCTSkip("The split view is not collapsed on this device.")
      }
      app.buttons["detail-show-in-sidebar"].tap()
      XCTAssertTrue(row("Inbox").waitForExistence(timeout: 5))
      select("Inbox")
      assertDetailLocation("Inbox")
    }
  #endif

  private func assertRow(
    _ first: String, appearsBefore second: String,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    let expected = XCTNSPredicateExpectation(
      predicate: NSPredicate { [self] _, _ in
        let a = row(first)
        let b = row(second)
        return a.exists && b.exists && a.frame.minY.isFinite && b.frame.minY.isFinite
          && a.frame.minY < b.frame.minY
      }, object: nil)
    XCTAssertEqual(
      XCTWaiter.wait(for: [expected], timeout: 5), .completed,
      "Expected \(first) before \(second)", file: file, line: line)
  }

  func testModifiedArrowsReorderSiblingsAndKeepSelection() throws {
    try requireSidebarBesideDetail()
    select("Inbox")
    assertRow("Inbox", appearsBefore: "Ideas")
    app.typeKey(.downArrow, modifierFlags: [.command, .option])
    assertRow("Ideas", appearsBefore: "Inbox")
    assertRow("Archive", appearsBefore: "Ideas")
    assertDetailLocation("Inbox")
    app.typeKey(.upArrow, modifierFlags: [.command, .option])
    assertRow("Inbox", appearsBefore: "Ideas")
    assertRow("Archive", appearsBefore: "Inbox")
    assertDetailLocation("Inbox")
    app.typeKey(.downArrow, modifierFlags: [])
    assertDetailLocation("Ideas")
  }

  func testReorderingAnExpandedFolderMovesTheWholeSubtree() throws {
    try requireSidebarBesideDetail()
    select("Work")
    app.typeKey(.downArrow, modifierFlags: [.command, .option])
    assertRow("Personal", appearsBefore: "Work")
    assertRow("Work", appearsBefore: "Weekly Report")
    assertRow("Weekly Report", appearsBefore: "Inbox")
    assertDetailLocation("Work")
    app.typeKey(.downArrow, modifierFlags: [])
    assertDetailLocation("Work › Clients")
  }

  func testReorderingIsDisabledInSearchResults() throws {
    try requireSidebarBesideDetail()
    search("i")
    select("Ideas")
    assertDetailLocation("Ideas")
    assertRow("Inbox", appearsBefore: "Ideas")
    app.typeKey(.upArrow, modifierFlags: [.command, .option])
    assertRow("Inbox", appearsBefore: "Ideas")
    assertDetailLocation("Ideas")
  }

  func testArrowKeysNavigateTheVisibleRows() throws {
    try requireSidebarBesideDetail()
    select("Inbox")
    #if os(macOS)
      // A row click must restore native keyboard focus even when the selection stays the same.
      let detailField = app.textFields["detail-name"]
      XCTAssertTrue(detailField.waitForExistence(timeout: 5))
      detailField.click()
      select("Inbox")
    #endif
    app.typeKey(.downArrow, modifierFlags: [])
    assertDetailLocation("Ideas")
    app.typeKey(.upArrow, modifierFlags: [])
    assertDetailLocation("Inbox")
  }

  func testHorizontalArrowsCollapseExpandAndEnterAFolder() throws {
    try requireSidebarBesideDetail()
    select("Work")
    app.typeKey(.leftArrow, modifierFlags: [])
    XCTAssertTrue(row("Weekly Report").waitForNonExistence(timeout: 5))
    app.typeKey(.rightArrow, modifierFlags: [])
    XCTAssertTrue(row("Weekly Report").waitForExistence(timeout: 5))
    app.typeKey(.rightArrow, modifierFlags: [])
    assertDetailLocation("Work › Clients")
    app.typeKey(.leftArrow, modifierFlags: [])
    assertDetailLocation("Work")
  }

  func testSectionHeadersToggleWithoutSelectingTheirContent() {
    app.terminate()
    app.launchArguments.append("-sample-section")
    app.launch()
    let header = app.descendants(matching: .any)
      .matching(NSPredicate(format: "label BEGINSWITH %@", "Favorites")).firstMatch
    XCTAssertTrue(header.waitForExistence(timeout: 5))
    XCTAssertTrue(row("Favorite Note").waitForExistence(timeout: 5))
    #if os(macOS)
      header.click()
    #else
      header.tap()
    #endif
    XCTAssertTrue(row("Favorite Note").waitForNonExistence(timeout: 5))
    // The header must stay collapsed: a second, delayed toggle used to reopen it after the
    // double-click interval.
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    XCTAssertFalse(row("Favorite Note").exists, "The section opened again by itself")
    #if os(macOS)
      header.click()
    #else
      header.tap()
    #endif
    XCTAssertTrue(row("Favorite Note").waitForExistence(timeout: 5))
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))
    XCTAssertTrue(row("Favorite Note").exists, "The section closed again by itself")
  }

  #if os(macOS)
    func testClickingASectionHeaderKeepsTheSelection() {
      app.terminate()
      app.launchArguments.append("-sample-section")
      app.launch()
      select("Inbox")
      assertDetailLocation("Inbox")
      let header = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label BEGINSWITH %@", "Favorites")).firstMatch
      XCTAssertTrue(header.waitForExistence(timeout: 5))
      header.click()
      XCTAssertTrue(row("Favorite Note").waitForNonExistence(timeout: 5))
      assertDetailLocation("Inbox")
    }

    func testCollapsingAFolderKeepsTheSelectionOfAHiddenRow() {
      select("Weekly Report")
      assertDetailLocation("Work › Weekly Report")
      let disclosure = app.outlineRows
        .containing(.any, identifier: "sidebar-row-Work").disclosureTriangles.firstMatch
      XCTAssertTrue(disclosure.waitForExistence(timeout: 5))
      disclosure.click()
      XCTAssertTrue(row("Weekly Report").waitForNonExistence(timeout: 5))
      assertDetailLocation("Work › Weekly Report")
    }
  #endif

  func testChangingAStatusUpdatesTheBadgeWithoutChangingSelection() throws {
    try requireSidebarBesideDetail()
    select("Inbox")
    let status = app.descendants(matching: .any).matching(identifier: "detail-status").firstMatch
    XCTAssertTrue(status.waitForExistence(timeout: 5))
    #if os(macOS)
      status.click()
      app.menuItems["New"].click()
      let inbox = app.outlines.firstMatch.descendants(matching: .outlineRow)
        .containing(.any, identifier: "sidebar-row-Inbox").firstMatch
      // Badges are static text, like the row's title; their text is the value.
      let badges = inbox.descendants(matching: .staticText)
        .matching(NSPredicate(format: "value == %@", "New"))
    #else
      status.tap()
      app.buttons["New"].firstMatch.tap()
      let badges = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Inbox", "New"))
    #endif
    XCTAssertTrue(badges.firstMatch.waitForExistence(timeout: 5))
    assertDetailLocation("Inbox")
    // Clearing a status hides the accessory while keeping the same selected element.
    #if os(macOS)
      status.click()
      app.menuItems["None"].click()
    #else
      status.tap()
      app.buttons["None"].firstMatch.tap()
    #endif
    XCTAssertTrue(badges.firstMatch.waitForNonExistence(timeout: 5))
    assertDetailLocation("Inbox")
  }

  func testSidebarPassesAccessibilityChecks() throws {
    #if os(iOS)
      var hasUnresolvedFontIssue = false
      var matchedFontIssues = 0
    #endif
    #if os(macOS)
      let types: XCUIAccessibilityAuditType = [.elementDetection, .sufficientElementDescription]
      // On macOS 27, SwiftUI and AppKit expose unnamed containers of their own, such as the
      // groups around the split view's columns and the search field, and a Touch Bar element.
      // The app can't name them; an accessibility label adds another group instead. Exempt only
      // such containers outside the outline; the outline and all controls are still audited.
      let outline = app.outlines.firstMatch
      XCTAssertTrue(outline.waitForExistence(timeout: 5))
      let outlineFrame = outline.frame
      func isFrameworkContainer(_ element: XCUIElement) -> Bool {
        [.group, .touchBar].contains(element.elementType) && element.label.isEmpty
          && !outlineFrame.contains(element.frame)
      }
    #else
      app.terminate()
      app.launchArguments += ["-sidebar-only", "-sample-section"]
      app.launch()
      let types: XCUIAccessibilityAuditType = [
        .elementDetection, .sufficientElementDescription, .dynamicType, .textClipped,
      ]
      // Reproduced with the unchanged 0.3.0 package in this same section fixture. Keep the
      // unresolved audit visible; unrelated issues and issues with an identifiable element fail.
      let options = XCTExpectedFailure.Options()
      options.isStrict = false
      options.issueMatcher = { issue in
        guard hasUnresolvedFontIssue, matchedFontIssues == 0,
          issue.compactDescription == "Dynamic Type font sizes are unsupported"
        else { return false }
        matchedFontIssues += 1
        return true
      }
      XCTExpectFailure(
        "Existing section Dynamic Type audit issue has no element to inspect; manual inspection remains open.",
        options: options)
    #endif
    try app.performAccessibilityAudit(for: types) { issue in
      #if os(iOS)
        hasUnresolvedFontIssue = issue.auditType == .dynamicType && issue.element == nil
      #endif
      print("Accessibility type \(issue.auditType.rawValue): \(issue.detailedDescription)")
      if let element = issue.element { print(element.debugDescription) }
      #if os(macOS)
        if issue.auditType == .sufficientElementDescription, let element = issue.element,
          isFrameworkContainer(element)
        {
          return true
        }
      #endif
      return false
    }
  }

  func testAddingToACollapsedFolderRevealsTheNewSelection() throws {
    try requireSidebarBesideDetail()
    select("Work")
    app.typeKey(.leftArrow, modifierFlags: [])
    XCTAssertTrue(row("Weekly Report").waitForNonExistence(timeout: 5))
    #if os(macOS)
      app.typeKey("n", modifierFlags: [.command, .option])
    #else
      app.buttons["Add"].tap()
      app.buttons["New Document"].firstMatch.tap()
    #endif
    XCTAssertTrue(row("New Document").waitForExistence(timeout: 5))
    XCTAssertTrue(row("Weekly Report").exists)
    assertDetailLocation("Work › New Document")
  }

  #if os(macOS)
    func testCommandOOpensInsteadOfRenaming() {
      select("Inbox")
      app.typeKey("o", modifierFlags: .command)
      XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
      XCTAssertTrue(app.sheets.staticTexts["Opened \"Inbox\""].exists)
    }

    func testCommandDownOpensInsteadOfRenaming() {
      select("Inbox")
      app.typeKey(.downArrow, modifierFlags: .command)
      XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
      XCTAssertTrue(app.sheets.staticTexts["Opened \"Inbox\""].exists)
    }

    func testReturnRenamesAndReturnsFocusToTheOutline() {
      select("Inbox")
      app.typeKey(.return, modifierFlags: [])
      let field = app.textFields["sidebar-row-Inbox"].firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.typeText("Renamed Inbox")
      app.typeKey(.return, modifierFlags: [])
      XCTAssertTrue(row("Renamed Inbox").waitForExistence(timeout: 5))
      app.typeKey("o", modifierFlags: .command)
      XCTAssertTrue(app.sheets.firstMatch.waitForExistence(timeout: 5))
      XCTAssertTrue(app.sheets.staticTexts["Opened \"Renamed Inbox\""].exists)
    }

    func testTypeSelectFindsAMatchingVisibleRow() {
      select("Work")
      app.typeKey("a", modifierFlags: [])
      assertDetailLocation("Archive")
    }
  #else
    func testAccessibilityTextSizesWrapRowTitles() {
      app.terminate()
      app.launchArguments.append("-sample-section")
      app.launch()
      let header = app.descendants(matching: .any)
        .matching(NSPredicate(format: "label BEGINSWITH %@", "Favorites")).firstMatch
      XCTAssertTrue(header.waitForExistence(timeout: 5))
      let standardHeaderHeight = header.frame.height
      app.terminate()
      app.launchArguments.append("-large-text")
      app.launch()
      let work = row("Work")
      let report = row("Weekly Report")
      XCTAssertTrue(work.waitForExistence(timeout: 5))
      XCTAssertTrue(report.waitForExistence(timeout: 5))
      XCTAssertGreaterThan(report.frame.height, work.frame.height)
      XCTAssertGreaterThan(header.frame.height, standardHeaderHeight)
    }

    func testInlineRenamingKeepsSpacesAndRestoresKeyboardNavigation() throws {
      try requireSidebarBesideDetail()
      app.terminate()
      app.launchArguments.append("-disable-animations")
      app.launch()
      select("Work")
      row("Work").press(forDuration: 1.2)
      app.buttons["Rename"].tap()
      let field = app.textFields.matching(NSPredicate(format: "identifier != %@", "detail-name"))
        .firstMatch
      XCTAssertTrue(field.waitForExistence(timeout: 5))
      field.typeText("Renamed Work\n")
      XCTAssertTrue(row("Renamed Work").waitForExistence(timeout: 5))
      app.typeKey(.downArrow, modifierFlags: [])
      assertDetailLocation("Renamed Work › Clients")
    }

    func testSpaceTogglesTheSelectedFolder() throws {
      try requireSidebarBesideDetail()
      select("Work")
      app.typeKey(" ", modifierFlags: [])
      XCTAssertTrue(row("Weekly Report").waitForNonExistence(timeout: 5))
      app.typeKey(" ", modifierFlags: [])
      XCTAssertTrue(row("Weekly Report").waitForExistence(timeout: 5))
    }

    func testHorizontalArrowsFollowRightToLeftLayout() throws {
      try requireSidebarBesideDetail()
      app.terminate()
      app.launchArguments.append("-right-to-left")
      app.launch()
      select("Work")
      app.typeKey(.rightArrow, modifierFlags: [])
      XCTAssertTrue(row("Weekly Report").waitForNonExistence(timeout: 5))
      app.typeKey(.leftArrow, modifierFlags: [])
      XCTAssertTrue(row("Weekly Report").waitForExistence(timeout: 5))
    }
  #endif

  // MARK: Search

  private func search(_ text: String) {
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5), "No search field")
    // Right after launch, the first keystrokes can get lost; type until the field has the text.
    for _ in 0..<3 where (field.value as? String) != text {
      #if os(macOS)
        field.click()
      #else
        field.tap()
      #endif
      field.typeText(text)
    }
    XCTAssertEqual(field.value as? String, text)
  }

  func testSearchingShowsOnlyMatchesAndTheFoldersLeadingToThem() {
    search("Contract")
    // Contract lives in Work › Clients › Globex, which the search opens.
    XCTAssertTrue(row("Contract").waitForExistence(timeout: 5))
    XCTAssertTrue(row("Globex").exists)
    XCTAssertFalse(row("Inbox").exists)
    XCTAssertFalse(row("Acme").exists)
  }

  #if os(macOS)
    func testDraggingIsOffWhileSearching() {
      search("Contract")
      XCTAssertTrue(row("Contract").waitForExistence(timeout: 5))
      drag("Contract", onto: "Work")
      select("Contract")
      assertDetailLocation("Work › Clients › Globex › Contract")
    }
  #endif

  // MARK: Context menus

  #if os(macOS)
    func testRightClickingARowShowsItsContextMenu() {
      let window = app.windows.firstMatch
      let report = row("Weekly Report")
      XCTAssertTrue(report.waitForExistence(timeout: 5))
      report.rightClick()
      // The row's own menu, not the one for empty space, which only offers adding.
      XCTAssertTrue(window.menuItems["Move to"].waitForExistence(timeout: 3))
      XCTAssertTrue(window.menuItems["Delete"].exists)
      app.typeKey(.escape, modifierFlags: [])
    }
  #endif

  // MARK: Drag and drop

  #if os(macOS)
    private func drag(_ source: String, onto target: String) {
      let source = row(source)
      let target = row(target)
      XCTAssertTrue(source.waitForExistence(timeout: 5))
      XCTAssertTrue(target.waitForExistence(timeout: 5))
      // The mouse-based variant: `press(forDuration:thenDragTo:)` synthesizes touches, which
      // start no AppKit drag session.
      source.click(forDuration: 0.6, thenDragTo: target)
    }

    func testDraggingADocumentOntoAFolderMovesItInside() {
      drag("Inbox", onto: "Archive")
      // The demo opens the folder that received the drop.
      XCTAssertTrue(row("Inbox").waitForExistence(timeout: 5))
      select("Inbox")
      assertDetailLocation("Archive › Inbox")
    }

    func testDraggingAFolderIntoItsOwnSubfolderIsRejected() {
      drag("Work", onto: "Clients")
      select("Work")
      assertDetailLocation("Work")
      select("Clients")
      assertDetailLocation("Work › Clients")
    }

    func testDroppingOntoADocumentInsertsNextToIt() {
      drag("Inbox", onto: "Recipes")
      select("Inbox")
      // Recipes is a document inside Personal, so Inbox lands next to it, not inside it.
      assertDetailLocation("Personal › Inbox")
      XCTAssertGreaterThan(row("Inbox").frame.minY, row("Recipes").frame.minY)
    }

    func testMovedFolderKeepsItsExpansion() {
      // Personal is expanded, so its children are visible; after the move they still are.
      drag("Personal", onto: "Archive")
      XCTAssertTrue(row("Recipes").waitForExistence(timeout: 5))
      select("Recipes")
      assertDetailLocation("Archive › Personal › Recipes")
    }
  #endif

  #if os(iOS)
    /// Long-presses a row and drags it to a point within another row: `0.5` is the middle, which
    /// drops onto the row; `0.05` its top edge, which inserts before it.
    private func drag(_ source: String, to target: String, at verticalOffset: CGFloat = 0.5) {
      // The context menu shares the long press with dragging; whether a synthesized press opens
      // the menu or lifts the row depends on timing. Drag tests therefore run without the menu,
      // which `testLongPressShowsTheContextMenu` covers on its own.
      if !app.launchArguments.contains("-disable-context-menus") {
        app.terminate()
        app.launchArguments.append("-disable-context-menus")
        app.launch()
      }
      let source = row(source)
      // Offsets refer to the whole list cell; the row's label is shorter than its cell.
      let target = cell(containing: target)
      XCTAssertTrue(source.waitForExistence(timeout: 5))
      XCTAssertTrue(target.waitForExistence(timeout: 5))
      source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        .press(
          forDuration: 1.0,
          thenDragTo: target.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: verticalOffset)),
          withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    private func cell(containing name: String) -> XCUIElement {
      app.cells.containing(.any, identifier: "sidebar-row-\(name)").firstMatch
    }

    func testSelectingOpensTheDetailAndNavigatingBackAllowsReopening() throws {
      select("Inbox")
      assertDetailLocation("Inbox")
      let back = app.navigationBars.buttons["Library"]
      guard back.waitForExistence(timeout: 2) else {
        throw XCTSkip("The split view is not collapsed on this device.")
      }
      back.tap()
      XCTAssertTrue(row("Inbox").waitForExistence(timeout: 5))
      // The selection was cleared on the way back, so the same row opens again.
      select("Inbox")
      assertDetailLocation("Inbox")
    }

    func testLongPressShowsTheContextMenu() {
      // Without animations, the app becomes idle while the menu is open.
      app.terminate()
      app.launchArguments.append("-disable-animations")
      app.launch()
      let inbox = row("Inbox")
      XCTAssertTrue(inbox.waitForExistence(timeout: 5))
      inbox.press(forDuration: 1.2)
      XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5), "No context menu appeared")
      XCTAssertTrue(app.buttons["Move to"].exists)
    }

    func testSwipingARowLeftDeletesIt() {
      let ideas = cell(containing: "Ideas")
      XCTAssertTrue(ideas.waitForExistence(timeout: 5))
      ideas.swipeLeft()
      let delete = app.buttons["Delete"].firstMatch
      XCTAssertTrue(delete.waitForExistence(timeout: 5), "No swipe action appeared")
      delete.tap()
      XCTAssertTrue(row("Ideas").waitForNonExistence(timeout: 5))
    }

    func testDroppingARowOntoAFolderMovesItInside() {
      // Archive is an empty folder, so only a drop onto it can place Inbox inside.
      drag("Inbox", to: "Archive")
      XCTAssertTrue(row("Inbox").waitForExistence(timeout: 5))
      select("Inbox")
      assertDetailLocation("Archive › Inbox")
    }

    func testDroppingAtTheTopEdgeOfARowInsertsBeforeIt() {
      drag("Ideas", to: "Work", at: 0.05)
      XCTAssertLessThan(row("Ideas").frame.minY, row("Work").frame.minY)
      select("Ideas")
      assertDetailLocation("Ideas")
    }

    func testDroppingOntoADocumentInsertsNextToIt() {
      // Recipes is a document inside Personal, so the demo redirects the drop next to it.
      drag("Inbox", to: "Recipes")
      select("Inbox")
      assertDetailLocation("Personal › Inbox")
    }
  #endif
}
